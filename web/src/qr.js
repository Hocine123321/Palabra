// A QR code as a plain element tree (no innerHTML, no inline styles: the page's CSP forbids both).
import qrcode from "qrcode-generator";

const QUIET = 4;

export function qrTree(text) {
  const qr = qrcode(0, "M");
  qr.addData(text);
  qr.make();
  const n = qr.getModuleCount();
  const size = n + QUIET * 2;
  let d = "";
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      if (qr.isDark(y, x)) d += `M${x + QUIET} ${y + QUIET}h1v1h-1z`;
    }
  }
  return {
    tag: "svg",
    attrs: { xmlns: "http://www.w3.org/2000/svg", viewBox: `0 0 ${size} ${size}`, role: "img", "shape-rendering": "crispEdges", class: "qr" },
    children: [
      { tag: "rect", attrs: { width: String(size), height: String(size), fill: "#ffffff" }, children: [] },
      { tag: "path", attrs: { d, fill: "#000000" }, children: [] },
    ],
  };
}
