// UI strings: the English text is the key; Arabic is looked up by it. A missing Arabic entry falls back to English.

export const KEYS = {
  "Palabra Mirroring": "مرآة Palabra",
  "Pair this computer": "اقرن هذا الحاسوب",
  "On your phone open Palabra, then Settings, Mirroring, Pair a Computer, and scan this code.":
    "على هاتفك افتح Palabra، ثم الإعدادات، ثم المرآة، ثم «اقرن حاسوبًا»، وامسح هذا الرمز.",
  "Waiting for your phone…": "في انتظار هاتفك…",
  "Pairing expired.": "انتهت مهلة الإقران.",
  "Pairing was cancelled.": "تم إلغاء الإقران.",
  "Something went wrong. Try again.": "حدث خطأ. حاول مرة أخرى.",
  "Start again": "ابدأ من جديد",
  "Cancel": "إلغاء",
  "Check the code": "تحقق من الرمز",
  "The code on your phone and on this screen must be the same. If they differ, cancel.":
    "يجب أن يتطابق الرمز على هاتفك وعلى هذه الشاشة. إن اختلفا فألغِ.",
  "Codes match": "الرمزان متطابقان",
  "Waiting for your phone to confirm…": "في انتظار تأكيد هاتفك…",
  "Your words": "كلماتك",
  "No words yet. Add words in the Palabra app on your phone.": "لا توجد كلمات بعد. أضف كلمات في تطبيق Palabra على هاتفك.",
  "Last updated": "آخر تحديث",
  "Not updated yet": "لم يتم التحديث بعد",
  "Refresh": "تحديث",
  "Updating…": "جارٍ التحديث…",
  "Offline: showing your saved copy.": "غير متصل: يتم عرض نسختك المحفوظة.",
  "Could not update. Showing your saved copy.": "تعذّر التحديث. يتم عرض نسختك المحفوظة.",
  "This computer was removed": "تمت إزالة هذا الحاسوب",
  "Pair it again from your phone to keep using Palabra here.": "اقرنه مرة أخرى من هاتفك لمتابعة استخدام Palabra هنا.",
  "Pair again": "اقرن مرة أخرى",
  "Loading…": "جارٍ التحميل…",
  "Phone synced": "آخر مزامنة للهاتف",
  "Still receiving from your phone…": "لا يزال الاستلام من هاتفك جاريًا…",
  "Not verified yet": "لم يتم التحقق بعد",
  "The phone has not synced for over a day, so this may be out of date.": "لم يتزامن الهاتف منذ أكثر من يوم، فقد تكون هذه البيانات قديمة.",
  "The server sent older data than this computer already has, so it was ignored. Showing your saved copy.": "أرسل الخادم بيانات أقدم مما لدى هذا الحاسوب، فتم تجاهلها. يتم عرض نسختك المحفوظة.",
  "Sections": "الأقسام",
  "Words": "الكلمات",
  "Study": "المراجعة",
  "Need Review": "تحتاج مراجعة",
  "Artifacts": "المنتجات",
  "Chat": "المحادثة",
  "Books": "الكتب",
  "Nothing here yet": "لا يوجد شيء هنا بعد",
  "That item is gone": "هذا العنصر لم يعد موجودًا",
  "Back to words": "العودة إلى الكلمات",
  "Details": "التفاصيل",
  "Examples": "أمثلة",
  "Meaning": "المعنى",
  "Usage and register": "الاستخدام والمستوى",
  "Register": "المستوى",
  "Forms": "الصيغ",
  "Similar words": "كلمات مشابهة",
  "Chart": "رسم بياني",
  "No data": "لا توجد بيانات",
  "Image": "صورة",
  "Couldn't load data": "تعذّر تحميل البيانات",
  "This page can't be shown here": "لا يمكن عرض هذه الصفحة هنا",
};

export function t(key, lang) {
  return lang === "ar" ? (KEYS[key] ?? key) : key;
}

export const pickLang = (navigatorLanguage) => (/^ar\b/i.test(navigatorLanguage ?? "") ? "ar" : "en");
export const dirFor = (lang) => (lang === "ar" ? "rtl" : "ltr");
