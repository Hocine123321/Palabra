// The latest chat, in order. Line breaks are kept as separate text nodes with a <br> between them.
import { h, screenFrame } from "../view.js";
import { arr, formatTime, isObject, parseTime, str } from "./util.js";

const lines = (text) => str(text).split("\n").flatMap((line, i) => (i ? [h("br"), line] : [line]));

export function chatScreen({ chat, lang, frame = {} }, tr) {
  const turns = isObject(chat) ? arr(chat.turns).filter(isObject) : [];
  const title = isObject(chat) && str(chat.title) ? chat.title : tr("Chat", lang);
  return screenFrame(
    { ...frame, title, titleDir: "auto", lang },
    tr,
    turns.length
      ? h(
          "ol",
          { class: "chat" },
          ...turns.map((turn) => {
            const at = parseTime(turn.createdAt);
            return h(
              "li",
              { class: `turn ${turn.role === "user" ? "turn-user" : "turn-assistant"}` },
              h("span", { class: "secondary" }, turn.role === "user" ? tr("You", lang) : tr("Palabra", lang), at !== null ? ` · ${formatTime(at, lang)}` : "", turn.status === "failed" ? ` · ${tr("Not sent", lang)}` : ""),
              h("p", { dir: "auto" }, ...lines(turn.text)),
            );
          }),
        )
      : h("p", { class: "empty" }, tr("Nothing here yet", lang)),
  );
}
