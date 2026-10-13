/* Palabra on-device math. Loaded after nerdamer.bundle.js into a JavaScriptCore context.
 *
 * palabraSolve(text) takes one cleaned problem ("x^2 - 4 = 0", "derivative of sin(x) x^2",
 * "integrate x^2 from 0 to 3", ...) and returns a JSON string:
 *   { ok: true,  kind, interpretation, answer, extras: [{ title, text }] }
 *   { ok: false, reason: "unsupported" | "error" }
 *
 * The rule: answer only what the engine gets right. Anything it is unsure about
 * (inequalities, trigonometric equations, base-10 logs, results it could not finish)
 * is "unsupported", and the app hands it to Gemini instead.
 */
(function (global) {
    var nd = global.nerdamer;
    var CONSTANTS = { pi: 1, e: 1, i: 1, Infinity: 1, infinity: 1 };

    function ok(kind, interpretation, answer, extras) {
        return JSON.stringify({ ok: true, kind: kind, interpretation: interpretation, answer: answer, extras: extras || [] });
    }
    function unsupported() { return JSON.stringify({ ok: false, reason: "unsupported" }); }

    /* ---------- text helpers ---------- */

    // Splits "a, (b, c), d" at the commas that are not inside brackets.
    function splitTopLevel(text) {
        var parts = [], depth = 0, current = "";
        for (var k = 0; k < text.length; k++) {
            var c = text.charAt(k);
            if (c === "(" || c === "[" || c === "{") depth++;
            if (c === ")" || c === "]" || c === "}") depth--;
            if (c === "," && depth === 0) { parts.push(current.trim()); current = ""; } else { current += c; }
        }
        if (current.trim() !== "") parts.push(current.trim());
        return parts;
    }

    // What the person typed, made digestible for the engine.
    function prepare(raw) {
        var s = String(raw);
        s = s.replace(/\|([^|]+)\|/g, "abs($1)");          // |x| -> abs(x)
        s = s.replace(/\bln\s*\(/gi, "log(");                // natural log is log() in the engine
        s = s.replace(/\binfinity\b/gi, "Infinity");
        s = s.replace(/∞/g, "Infinity");
        // Only single-letter unknowns and the functions the engine knows: a stray word ("degrees", "mod")
        // would be read as a product of unknowns and give nonsense, so it goes to Gemini instead.
        var stripped = s.replace(/\b(?:sqrt|cbrt|abs|log|exp|sinh|cosh|tanh|asin|acos|atan|sin|cos|tan|sec|csc|cot|pi|Infinity)\b/g, "");
        if (/[A-Za-z]{2,}/.test(stripped)) throw new Error("unsupported");
        return s;
    }

    // Reads nicely: sqrt, pi, infinity, "2x" instead of "2*x".
    function pretty(text) {
        var s = String(text);
        s = s.replace(/\(([^()]+)\)\^\(1\/2\)/g, "sqrt($1)");
        s = s.replace(/\b([A-Za-z0-9.]+)\^\(1\/2\)/g, "sqrt($1)");
        s = s.replace(/\b([A-Za-z0-9.]+)\^\(1\/3\)/g, "cbrt($1)");
        s = s.replace(/(\d)\*([A-Za-z(])/g, "$1$2");
        s = s.replace(/\blog\(/g, "ln(");
        s = s.replace(/\bpi\b/g, "π");
        s = s.replace(/-?Infinity/g, function (m) { return m.charAt(0) === "-" ? "-∞" : "∞"; });
        s = s.replace(/\^-(\d+)/g, "^(-$1)");
        s = s.replace(/\*([A-Za-z0-9.]+)\^\(-1\)/g, "/$1");
        return cleanNumber(s);
    }

    function hasUnfinished(text) {
        return /(?:integrate|defint|limit|solve|diff|sum|product)\s*\(/.test(text) || /NaN|undefined/.test(text);
    }

    function freeSymbols(expr) {
        var vars = nd(expr).variables();
        var out = [];
        for (var k = 0; k < vars.length; k++) if (!CONSTANTS[vars[k]] && out.indexOf(vars[k]) < 0) out.push(vars[k]);
        return out.sort();
    }

    // A decimal for display: at most 10 significant digits, no trailing zeros. null when not a real number.
    function decimalOf(expr) {
        var text;
        try { text = nd(expr).evaluate().text("decimals"); } catch (e) { return null; }
        if (/i/.test(text) && !/^-?[0-9.e+-]+$/.test(text)) return null;
        var fraction = /^(-?\d+)\/(\d+)$/.exec(text);
        var value = fraction ? Number(fraction[1]) / Number(fraction[2]) : Number(text);
        if (!isFinite(value)) return null;
        return String(parseFloat(value.toPrecision(10)));
    }

    function isWholeNumber(text) { return /^-?\d+$/.test(String(text).trim()); }
    function cleanNumber(text) { return String(text).replace(/(\d)\.0+\b/g, "$1"); }

    /* ---------- numeric cross-checks ----------
     * Every answer is compared with plain arithmetic before it is shown, so a symbolic slip
     * becomes "unsupported" (and goes to Gemini) instead of a wrong answer. */

    var SAMPLES = [0.7, 1.3, 2.1, -0.9, 3.4];

    function compile(expr, vars) { return nd(expr).buildFunction(vars); }
    function finite(y) { return typeof y === "number" && isFinite(y); }
    function close(a, b, tolerance) { return Math.abs(a - b) <= (tolerance || 1e-6) * Math.max(1, Math.abs(a), Math.abs(b)); }
    function pointFor(vars, k) { return vars.map(function (_, j) { return SAMPLES[(k + j) % SAMPLES.length]; }); }

    // Same values wherever both are defined, at no fewer than two sample points.
    function sameFunction(a, b, vars) {
        var fa = compile(a, vars), fb = compile(b, vars), compared = 0;
        for (var k = 0; k < SAMPLES.length; k++) {
            var args = pointFor(vars, k), ya, yb;
            try { ya = fa.apply(null, args); yb = fb.apply(null, args); } catch (e) { continue; }
            if (!finite(ya) || !finite(yb)) continue;
            compared++;
            if (!close(ya, yb)) return false;
        }
        return compared >= 2;
    }

    // `derivative` really is the derivative of `base` with respect to vars[index].
    function derivativeMatches(base, derivative, vars, index) {
        var fb = compile(base, vars), fd = compile(derivative, vars), compared = 0, h = 1e-5;
        for (var k = 0; k < SAMPLES.length; k++) {
            var args = pointFor(vars, k), up = args.slice(), down = args.slice(), slope, expected;
            up[index] += h; down[index] -= h;
            try { slope = (fb.apply(null, up) - fb.apply(null, down)) / (2 * h); expected = fd.apply(null, args); } catch (e) { continue; }
            if (!finite(slope) || !finite(expected)) continue;
            compared++;
            if (!close(slope, expected, 1e-4)) return false;
        }
        return compared >= 2;
    }

    // Composite Simpson's rule; null when the integrand is not finite on [a, b].
    function simpson(expr, v, a, b) {
        var f = compile(expr, [v]), n = 2000, h = (b - a) / n, total = 0;
        for (var k = 0; k <= n; k++) {
            var y;
            try { y = f(a + k * h); } catch (e) { return null; }
            if (!finite(y)) return null;
            total += y * (k === 0 || k === n ? 1 : (k % 2 === 1 ? 4 : 2));
        }
        return total * h / 3;
    }

    function pointValue(text) {
        if (/^-?Infinity$/.test(text.trim())) return text.trim().charAt(0) === "-" ? -Infinity : Infinity;
        var d = decimalOf(text);
        return d === null ? NaN : Number(d);
    }

    function variableInExponent(expr, v) {
        var pattern = new RegExp("\\b" + v + "\\b");
        for (var k = 0; k < expr.length; k++) {
            if (expr.charAt(k) !== "^") continue;
            var j = k + 1, token = "";
            if (expr.charAt(j) === "-") j++;
            if (expr.charAt(j) === "(") {
                var depth = 0;
                for (; j < expr.length; j++) {
                    var c = expr.charAt(j);
                    if (c === "(") depth++;
                    if (c === ")") { depth--; if (depth === 0) { token += c; break; } }
                    token += c;
                }
            } else {
                while (j < expr.length && /[A-Za-z0-9.]/.test(expr.charAt(j))) token += expr.charAt(j++);
            }
            if (pattern.test(token)) return true;
        }
        return false;
    }

    /* ---------- solving ---------- */

    function chooseVariable(expr, asked) {
        if (asked) return asked;
        var vars = freeSymbols(expr);
        if (vars.length === 0) return null;
        return vars.indexOf("x") >= 0 ? "x" : vars[0];
    }

    // Solutions of "lhs = rhs" for one variable, checked by substituting them back.
    function solveFor(equation, variable) {
        var raw = nd.solve(equation, variable).toString();
        var inner = raw.replace(/^[\[{]/, "").replace(/[\]}]$/, "");
        var candidates = inner.trim() === "" ? [] : splitTopLevel(inner);
        var sides = equation.split("=");
        var residual = "(" + sides[0] + ")-(" + sides[1] + ")";
        var kept = [];
        for (var k = 0; k < candidates.length; k++) {
            var candidate = candidates[k];
            var check;
            try {
                var sub = {}; sub[variable] = nd(candidate).evaluate().text();
                check = nd(residual, sub).evaluate().text("decimals");
            } catch (e) { continue; }
            var magnitude = Math.abs(Number(check));
            var complexRoot = /i/.test(check);
            if (!complexRoot && !(magnitude < 1e-7)) continue;   // an extraneous root: drop it
            if (kept.indexOf(candidate) < 0) kept.push(candidate);
        }
        return kept;
    }

    function sortRoots(roots) {
        var keyed = roots.map(function (r) { var d = decimalOf(r); return { r: r, d: d === null ? Infinity : Number(d) }; });
        keyed.sort(function (a, b) { return a.d - b.d; });
        return keyed.map(function (k) { return k.r; });
    }

    function solveOne(equation, asked) {
        if (/\b(?:sin|cos|tan|sec|csc|cot|asin|acos|atan)\b/.test(equation)) return unsupported(); // general solutions repeat
        var sides = equation.split("=");
        if (sides.length !== 2 || sides[0].trim() === "" || sides[1].trim() === "") return unsupported();
        var residual = "(" + sides[0] + ")-(" + sides[1] + ")";
        var variable = chooseVariable(residual, asked);
        if (variable === null) {
            // No unknown: is the statement true?
            var difference = decimalOf(residual);
            if (difference === null) return unsupported();
            return ok("check", equation, Math.abs(Number(difference)) < 1e-9 ? "True" : "False");
        }
        // Exponentials, logarithms and high degrees can have roots the engine does not list: leave them to Gemini.
        if (/\b(?:exp|log)\s*\(/.test(equation) || variableInExponent(equation, variable)) return unsupported();
        var degree = nd("deg(" + residual + "," + variable + ")").text();
        if (/^\d+$/.test(degree) && Number(degree) > 4) return unsupported();
        var roots = sortRoots(solveFor(equation, variable));
        if (roots.length === 0) return unsupported();
        var shown = roots.map(function (r) { return variable + " = " + pretty(r); });
        var extras = [];
        var approx = [];
        var anyApprox = false;
        for (var k = 0; k < roots.length; k++) {
            var d = isWholeNumber(roots[k]) ? roots[k] : decimalOf(roots[k]);
            if (d !== null && !isWholeNumber(roots[k])) anyApprox = true;
            approx.push(d === null ? null : variable + " ≈ " + d);
        }
        if (anyApprox && approx.indexOf(null) < 0) extras.push({ title: "Decimal approximation", text: approx.join(" or ") });
        return ok("solve", equation, shown.join(" or "), extras);
    }

    // Linear systems by elimination: solve one equation for one unknown, substitute, repeat.
    function solveLinearSystem(equations) {
        var residuals = equations.map(function (e) {
            var sides = e.split("=");
            return "(" + sides[0] + ")-(" + sides[1] + ")";
        });
        var vars = [];
        residuals.forEach(function (r) { freeSymbols(r).forEach(function (v) { if (vars.indexOf(v) < 0) vars.push(v); }); });
        vars.sort();
        if (vars.length !== equations.length || vars.length > 4) return unsupported();
        // Every equation must be linear: all second derivatives vanish.
        for (var a = 0; a < residuals.length; a++) {
            for (var b = 0; b < vars.length; b++) {
                for (var c = 0; c < vars.length; c++) {
                    var second = nd("diff(diff(" + residuals[a] + "," + vars[b] + ")," + vars[c] + ")").text();
                    if (second !== "0") return unsupported();
                }
            }
        }
        var rows = residuals.slice();
        var solved = [];   // [{ v, expr }] in elimination order
        for (var step = 0; step < vars.length; step++) {
            var v = vars[step];
            var expr = null;
            for (var r = step; r < rows.length && expr === null; r++) {
                var sol = splitTopLevel(nd.solve(rows[r] + "=0", v).toString().replace(/^[\[{]/, "").replace(/[\]}]$/, ""));
                if (sol.length === 1 && sol[0] !== "") {
                    expr = sol[0];
                    var swap = rows[step]; rows[step] = rows[r]; rows[r] = swap;
                }
            }
            if (expr === null) return unsupported();
            solved.push({ v: v, expr: expr });
            for (var t = step + 1; t < rows.length; t++) rows[t] = nd(rows[t]).sub(v, "(" + expr + ")").expand().text();
        }
        // Back-substitute from the last unknown up.
        var values = {};
        for (var s = solved.length - 1; s >= 0; s--) {
            var e = solved[s].expr;
            for (var key in values) e = nd(e).sub(key, "(" + values[key] + ")").text();
            values[solved[s].v] = nd(e).text("fractions");
        }
        // Check every original equation.
        for (var q = 0; q < residuals.length; q++) {
            var subs = {};
            for (var name in values) subs[name] = nd(values[name]).evaluate().text();
            var residue = Number(nd(residuals[q], subs).evaluate().text("decimals"));
            if (!(Math.abs(residue) < 1e-7)) return unsupported();
        }
        var shown = vars.map(function (name) { return name + " = " + pretty(values[name]); });
        var extras = [];
        var anyApprox = vars.some(function (name) { return !isWholeNumber(values[name]); });
        if (anyApprox) {
            var approx = vars.map(function (name) { var d = decimalOf(values[name]); return d === null ? null : name + " ≈ " + d; });
            if (approx.indexOf(null) < 0) extras.push({ title: "Decimal approximation", text: approx.join(", ") });
        }
        return ok("system", equations.join("; "), shown.join(", "), extras);
    }

    /* ---------- calculus and algebra ---------- */

    function derivative(expr, variable) {
        var v = variable || chooseVariable(expr, null) || "x";
        var out = nd("diff(" + expr + "," + v + ")").text();
        if (hasUnfinished(out)) return unsupported();
        var dvars = freeSymbols(expr + "+" + v);
        if (!derivativeMatches(expr, out, dvars, dvars.indexOf(v))) return unsupported();
        return ok("derivative", "d/d" + v + " (" + expr + ")", pretty(out));
    }

    function integral(expr, variable, lower, upper) {
        var v = variable || chooseVariable(expr, null) || "x";
        if (lower !== undefined && upper !== undefined) {
            var value = nd("defint(" + expr + "," + v + "," + lower + "," + upper + ")").text("fractions");
            if (hasUnfinished(value)) return unsupported();
            if (/^-?\d*\.\d+(?:e[+-]?\d+)?$/i.test(value)) { var rounded = decimalOf(value); if (rounded !== null) value = rounded; }
            var a = pointValue(lower), b = pointValue(upper), exact = pointValue(value);
            if (!isFinite(a) || !isFinite(b) || !isFinite(exact)) return unsupported();
            var numeric = simpson(expr, v, a, b);
            if (numeric === null || !close(numeric, exact, 1e-4)) return unsupported();
            var extras = [];
            var d = decimalOf(value);
            if (d !== null && !isWholeNumber(value)) extras.push({ title: "Decimal approximation", text: d });
            return ok("definite integral", "∫[" + lower + ", " + upper + "] " + expr + " d" + v, pretty(value), extras);
        }
        var out = nd("integrate(" + expr + "," + v + ")").text();
        if (hasUnfinished(out)) return unsupported();
        var ivars = freeSymbols(expr + "+" + out + "+" + v);
        if (!derivativeMatches(out, expr, ivars, ivars.indexOf(v))) return unsupported();
        return ok("integral", "∫ " + expr + " d" + v, pretty(out) + " + C");
    }

    function limit(expr, variable, point) {
        var target = point.replace(/\binfinity\b/gi, "Infinity");
        var out = nd("limit(" + expr + "," + variable + "," + target + ")").text("fractions");
        if (hasUnfinished(out) || /\^-1$/.test(out)) return unsupported();
        var L = pointValue(out), at = pointValue(target);
        if (!isFinite(L) || isNaN(at)) return unsupported();
        var g = compile(expr, [variable]), probes = isFinite(at) ? [at + 1e-5, at - 1e-5] : [at > 0 ? 1e7 : -1e7];
        for (var q = 0; q < probes.length; q++) {
            var y;
            try { y = g(probes[q]); } catch (e) { return unsupported(); }
            if (!finite(y) || !close(y, L, 1e-3)) return unsupported();
        }
        return ok("limit", "lim " + variable + "→" + point + " of " + expr, pretty(out));
    }

    function rewrite(kind, expr) {
        var out = nd(kind + "(" + expr + ")").text("fractions");
        if (hasUnfinished(out)) return unsupported();
        var rvars = freeSymbols(expr);
        if (rvars.length > 0 && !sameFunction(expr, out, rvars)) return unsupported();
        return ok(kind, kind + " " + expr, pretty(out));
    }

    // A bare expression: a number, or something to simplify.
    function evaluateExpression(expr) {
        var vars = freeSymbols(expr);
        if (vars.length === 0) {
            var exact = nd(expr).text("fractions");
            if (hasUnfinished(exact)) return unsupported();
            var extras = [];
            var d = decimalOf(expr);
            if (d !== null && !isWholeNumber(exact)) extras.push({ title: "Decimal approximation", text: d });
            return ok("number", expr, pretty(exact), extras);
        }
        // The shortest equivalent form leads; the other forms follow as alternates.
        var forms = [["Simplified form", pretty(nd(expr).text())],
                     ["Factored form", null, "factor"],
                     ["Expanded form", null, "expand"]];
        var candidates = [];
        forms.forEach(function (form) {
            try {
                var text = form[1] !== null ? form[1] : pretty(nd(form[2] + "(" + expr + ")").text());
                if (hasUnfinished(text) || !sameFunction(expr, text, vars)) return;
                if (candidates.some(function (c) { return c.text === text; })) return;
                candidates.push({ title: form[0], text: text });
            } catch (e) { /* skip this form */ }
        });
        if (candidates.length === 0) return unsupported();
        var best = 0;
        for (var c = 1; c < candidates.length; c++) if (candidates[c].text.length < candidates[best].text.length) best = c;
        var lead = candidates.splice(best, 1)[0];
        var alternates = candidates.filter(function (c) { return c.title !== "Simplified form" && c.text.length <= 60; });
        return ok("simplify", expr, lead.text, alternates);
    }

    /* ---------- reading the problem ---------- */

    function route(text) {
        var s = text.trim().replace(/[?.]+$/, "").trim();
        var m;

        if ((m = /^(?:find |compute |calculate |evaluate )?(?:the )?definite integral of (.+?) from (.+?) to (.+?)(?: d([a-z]))?$/i.exec(s)) ||
            (m = /^(?:find |compute |calculate |evaluate )?(?:the )?integral of (.+?) from (.+?) to (.+?)(?: d([a-z]))?$/i.exec(s)) ||
            (m = /^integrate (.+?) from (.+?) to (.+?)(?: d([a-z]))?$/i.exec(s))) {
            return integral(prepare(m[1]), m[4], prepare(m[2]), prepare(m[3]));
        }
        if ((m = /^(?:find |compute |calculate |evaluate )?(?:the )?(?:indefinite )?(?:integral|antiderivative) of (.+?)(?: d([a-z]))?$/i.exec(s)) ||
            (m = /^integrate (.+?)(?: d([a-z]))?$/i.exec(s)) ||
            (m = /^∫\s*(.+?)(?: d([a-z]))?$/.exec(s))) {
            return integral(prepare(m[1]), m[2]);
        }
        if ((m = /^(?:find |compute |calculate )?(?:the )?derivative of (.+?)(?: (?:with respect to|wrt) ([a-z]))?$/i.exec(s))) {
            return derivative(prepare(m[1]), m[2]);
        }
        if ((m = /^d\/d([a-z])\s*(.+)$/i.exec(s))) return derivative(prepare(m[2]), m[1]);
        if ((m = /^(?:find |compute |calculate )?(?:the )?limit of (.+?) as ([a-z]) (?:->|→|approaches|tends to|to) (.+)$/i.exec(s))) {
            return limit(prepare(m[1]), m[2], prepare(m[3]));
        }
        if ((m = /^lim\s*_?\(?\s*([a-z])\s*(?:->|→)\s*([^)\s]+)\s*\)?\s*(.+)$/i.exec(s))) {
            return limit(prepare(m[3]), m[1], prepare(m[2]));
        }
        if ((m = /^(factor|factorise|factorize)\s+(.+)$/i.exec(s))) return rewrite("factor", prepare(m[2]));
        if ((m = /^(expand|simplify)\s+(.+)$/i.exec(s))) return rewrite(m[1].toLowerCase(), prepare(m[2]));

        var forVariable;
        if ((m = /^solve\s+(.+?)(?:\s+for\s+([a-z]))?$/i.exec(s))) { s = m[1]; forVariable = m[2]; }

        // Several equations: a system.
        var statements = s.split(/\s*;\s*|\s+and\s+/i).filter(function (p) { return p.trim() !== ""; });
        if (statements.length === 1 && /,/.test(s) && s.split("=").length > 2) {
            var viaComma = splitTopLevel(s);
            if (viaComma.every(function (p) { return p.indexOf("=") > 0; })) statements = viaComma;
        }
        statements = statements.map(prepare);
        if (statements.length > 1) {
            if (!statements.every(function (p) { return /^[^<>=!]+=[^<>=!]+$/.test(p); })) return unsupported();
            return solveLinearSystem(statements);
        }

        var p = prepare(s);
        if (/[<>]|!=|≠/.test(p)) return unsupported();           // inequalities: not reliable here
        if (/\blog\s*\(/.test(p) && !/\bln\b/i.test(s)) return unsupported(); // log means base 10 to most people
        if (/°|%/.test(p)) return unsupported();
        if (p.indexOf("=") >= 0) return solveOne(p, forVariable);
        return evaluateExpression(p);
    }

    global.palabraSolve = function (text) {
        try {
            if (!nd) return JSON.stringify({ ok: false, reason: "error" });
            return route(String(text));
        } catch (error) {
            return unsupported();
        }
    };
})(this);
