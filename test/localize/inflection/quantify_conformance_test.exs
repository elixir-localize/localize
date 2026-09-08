defmodule Localize.Inflection.QuantifyConformanceTest do
  use ExUnit.Case, async: false

  alias Localize.Inflection.{Concept, Quantify, SpeakableString}

  # Each row: {index, concept string, constraints, formatted number,
  # category, number, expected, assert mode}.
  # Extracted from the upstream QuantifyTest.cpp via spec-quantify.md
  # (section 6). Formatted numbers are the values the upstream C++
  # factories produced internally; they are caller inputs for the port.
  @cases %{
    en: [
      {1, "yen", %{}, "1", :one, 1, "1 yen", :full},
      {2, "yen", %{}, "2", :other, 2, "2 yen", :full},
      {3, "kilometer", %{}, "1", :one, 1, "1 kilometer", :full},
      {4, "kilometer", %{}, "2", :other, 2, "2 kilometers", :full}
    ],
    th: [
      {1, "restaurant", %{}, "1", :other, 1, "restaurant 1", :full},
      {2, "restaurant", %{}, "2", :other, 2, "restaurant 2", :full}
    ],
    ko: [
      {1, "restaurant", %{}, "1", :other, 1, "1 restaurant", :full},
      {2, "restaurant", %{}, "2", :other, 2, "2 restaurant", :full},
      {3, "개", %{}, "3", :other, 3, "3개", :full},
      {4, "Word", %{"measure" => "Blah"}, "2", :other, 2, "2 Word Blah", :full}
    ],
    ar: [
      {1, "رسالة", %{}, {"٠", "صفر"}, :zero, 0, {"٠ رسالة", "صفر رسالة"}, :full},
      {2, "رسالة", %{}, "١", :one, 1, "رسالة", :full},
      {3, "رسالة", %{"case" => "accusative"}, "١", :one, 1, "رسالة", :full},
      {4, "رسالة", %{}, "٢", :two, 2, "رسالتان", :full},
      {5, "رسالة", %{"case" => "accusative"}, "٢", :two, 2, "رسالتين", :full},
      {6, "رسالة", %{"case" => "genitive"}, "٢", :two, 2, "رسالتين", :full},
      {7, "رسالة", %{}, {"٣", "ثلاثة"}, :few, 3, {"٣ رسائل", "ثلاثة رسائل"}, :full},
      {8, "رسالة", %{}, {"١١", "إحدى عشر"}, :many, 11, {"١١ رسالة", "إحدى عشر رسالة"}, :full},
      {9, "رسالة", %{}, {"١٠٠", "مائة"}, :other, 100, {"١٠٠ رسالة", "مائة رسالة"}, :full},
      {10, "تذكير", %{}, "١", :one, 1, "تذكير", :full},
      {11, "تذكير", %{"case" => "accusative"}, "١", :one, 1, "تذكيرا", :full},
      {12, "تذكير", %{"case" => "genitive"}, "١", :one, 1, "تذكير", :full},
      {13, "تذكير", %{}, "٢", :two, 2, "تذكيران", :full},
      {14, "تذكير", %{"case" => "accusative"}, "٢", :two, 2, "تذكيرين", :full},
      {15, "تذكير", %{"case" => "genitive"}, "٢", :two, 2, "تذكيرين", :full},
      {16, "تذكير", %{}, {"١١", "إحدى عشر"}, :many, 11, {"١١ تذكيرا", "إحدى عشر تذكيرا"}, :full},
      {17, "تذكير", %{"case" => "accusative"}, {"١١", "إحدى عشر"}, :many, 11,
       {"١١ تذكيرا", "إحدى عشر تذكيرا"}, :full},
      {18, "تذكير", %{"case" => "genitive"}, {"١١", "إحدى عشر"}, :many, 11,
       {"١١ تذكيرا", "إحدى عشر تذكيرا"}, :full},
      {19, "تذكير", %{}, {"١٠٠", "مائة"}, :other, 100, {"١٠٠ تذكير", "مائة تذكير"}, :full},
      {20, "تذكير", %{"case" => "accusative"}, {"١٠٠", "مائة"}, :other, 100,
       {"١٠٠ تذكير", "مائة تذكير"}, :full},
      {21, "تذكير", %{"case" => "genitive"}, {"١٠٠", "مائة"}, :other, 100,
       {"١٠٠ تذكير", "مائة تذكير"}, :full},
      {22, "شربة", %{"definiteness" => "construct"}, "١", :one, 1, "شربة", :full},
      {23, "شربة", %{"definiteness" => "construct", "case" => "accusative"}, "١", :one, 1, "شربة",
       :full},
      {24, "شربة", %{"definiteness" => "construct", "case" => "genitive"}, "١", :one, 1, "شربة",
       :full},
      {25, "شربة", %{"definiteness" => "construct"}, "٢", :two, 2, "شربتا", :full},
      {26, "شربة", %{"definiteness" => "construct", "case" => "accusative"}, "٢", :two, 2,
       "شربتي", :full},
      {27, "شربة", %{"definiteness" => "construct", "case" => "genitive"}, "٢", :two, 2, "شربتي",
       :full},
      {28, "شربة", %{"definiteness" => "construct"}, {"١١", "إحدى عشر"}, :many, 11,
       {"١١ شربة", "إحدى عشر شربة"}, :full},
      {29, "شربة", %{"definiteness" => "construct"}, {"١٠٠", "مائة"}, :other, 100,
       {"١٠٠ شربة", "مائة شربة"}, :full}
    ],
    he: [
      {1, "מכונית", %{}, {"0", "אפס"}, :other, 0, "0 מכוניות", :print},
      {2, "מכונית", %{}, "אחת", :one, 1, "מכונית אחת", :print},
      {3, "מכונית", %{}, "שתי", :two, 2, "שתי מכוניות", :print},
      {4, "מכונית", %{}, {"3", "שלוש"}, :other, 3, "3 מכוניות", :print},
      {5, "מכונית", %{"definiteness" => "definite"}, {"0", "אפס"}, :other, 0, "0 המכוניות",
       :print},
      {6, "מכונית", %{"definiteness" => "definite"}, "היחידה", :one, 1, "המכונית היחידה", :print},
      {7, "מכונית", %{"definiteness" => "definite"}, "שתי", :two, 2, "שתי המכוניות", :print},
      {8, "מכונית", %{"definiteness" => "definite"}, {"3", "שלוש"}, :other, 3, "3 המכוניות",
       :print},
      {9, "ספר", %{}, {"0", "אפס"}, :other, 0, "0 ספרים", :print},
      {10, "ספר", %{}, "אחד", :one, 1, "ספר אחד", :print},
      {11, "ספר", %{}, "שני", :two, 2, "שני ספרים", :print},
      {12, "ספר", %{}, {"3", "שלושה"}, :other, 3, "3 ספרים", :print},
      {13, "ספר", %{"definiteness" => "definite"}, "0", :other, 0, "0 הספרים", :print},
      {14, "ספר", %{"definiteness" => "definite"}, "היחיד", :one, 1, "הספר היחיד", :print},
      {15, "ספר", %{"definiteness" => "definite"}, "שני", :two, 2, "שני הספרים", :print},
      {16, "ספר", %{"definiteness" => "definite"}, "3", :other, 3, "3 הספרים", :print},
      {17, "בת", %{}, "0", :other, 0, "0 בנות", :print},
      {18, "בת", %{}, "אחת", :one, 1, "בת אחת", :print},
      {19, "בת", %{}, "שתי", :two, 2, "שתי בנות", :print},
      {20, "בת", %{}, "3", :other, 3, "3 בנות", :print},
      {21, "בת", %{"definiteness" => "definite"}, "0", :other, 0, "0 הבנות", :print},
      {22, "בת", %{"definiteness" => "definite"}, "היחידה", :one, 1, "הבת היחידה", :print},
      {23, "בת", %{"definiteness" => "definite"}, "שתי", :two, 2, "שתי הבנות", :print},
      {24, "בת", %{"definiteness" => "definite"}, "3", :other, 3, "3 הבנות", :print},
      {25, "חודש", %{}, "0", :other, 0, "0 חודשים", :print},
      {26, "חודש", %{}, "1", :one, 1, "חודש", :print},
      {27, "חודש", %{}, "3", :other, 3, "3 חודשים", :print},
      {28, "מטר", %{}, {"11", "אחד עשר"}, :other, 11, {"11 מטרים", "אחד עשר מטרים"}, :full},
      {29, "מטר", %{}, {"50", "חמישים"}, :other, 50, {"50 מטרים", "חמישים מטרים"}, :full},
      {30, "חתול", %{}, {"0", "אפס"}, :other, 0, {"0 חתולים", "אפס חתולים"}, :full},
      {31, "חתול", %{}, "אחד", :one, 1, "חתול אחד", :full},
      {32, "חתול", %{}, "שני", :two, 2, "שני חתולים", :full},
      {33, "חתול", %{}, {"3", "שלושה"}, :other, 3, {"3 חתולים", "שלושה חתולים"}, :full},
      {34, "חתול", %{"definiteness" => "definite"}, {"0", "אפס"}, :other, 0,
       {"0 החתולים", "אפס החתולים"}, :full},
      {35, "חתול", %{"definiteness" => "definite"}, "היחיד", :one, 1, "החתול היחיד", :full},
      {36, "חתול", %{"definiteness" => "definite"}, "שני", :two, 2, "שני החתולים", :full},
      {37, "חתול", %{"definiteness" => "definite"}, {"3", "שלושת"}, :other, 3,
       {"3 החתולים", "שלושת החתולים"}, :full},
      {38, "שניה", %{}, {"30", "שלושים"}, :other, 30, {"30 שניות", "שלושים שניות"}, :full}
    ],
    it: [
      {1, "settimana", %{}, {"0", "zero"}, :other, 0, {"0 settimane", "zero settimane"}, :full},
      {2, "settimana", %{}, "una ", :one, 1, "una settimana", :full},
      {3, "settimana", %{}, {"2", "due"}, :other, 2, {"2 settimane", "due settimane"}, :full},
      {4, "settimana", %{}, {"3", "tre"}, :other, 3, {"3 settimane", "tre settimane"}, :full},
      {5, "metro", %{}, {"0", "zero"}, :other, 0, {"0 metri", "zero metri"}, :full},
      {6, "metro", %{}, "un ", :one, 1, "un metro", :full},
      {7, "metro", %{}, {"2", "due"}, :other, 2, {"2 metri", "due metri"}, :full},
      {8, "metro", %{}, {"3", "tre"}, :other, 3, {"3 metri", "tre metri"}, :full},
      {9, "ora", %{}, {"0", "zero"}, :other, 0, {"0 ore", "zero ore"}, :full},
      {10, "ora", %{}, "un’", :one, 1, "un’ora", :full},
      {11, "ora", %{}, {"2", "due"}, :other, 2, {"2 ore", "due ore"}, :full},
      {12, "ora", %{}, {"3", "tre"}, :other, 3, {"3 ore", "tre ore"}, :full},
      {13, "yen", %{}, {"0", "zero"}, :other, 0, {"0 yen", "zero yen"}, :full},
      {14, "yen", %{}, "uno ", :one, 1, "uno yen", :full},
      {15, "yen", %{}, {"2", "due"}, :other, 2, {"2 yen", "due yen"}, :full},
      {16, "yen", %{}, {"3", "tre"}, :other, 3, {"3 yen", "tre yen"}, :full}
    ],
    es: [
      {1, "nota", %{}, {"1", "una"}, :one, 1, {"1 nota", "una nota"}, :full},
      {2, "nota", %{}, {"2", "dos"}, :other, 2, {"2 notas", "dos notas"}, :full},
      {3, "recordatorio", %{}, {"1", "un"}, :one, 1, {"1 recordatorio", "un recordatorio"},
       :full},
      {4, "recordatorio", %{}, {"2", "dos"}, :other, 2, {"2 recordatorios", "dos recordatorios"},
       :full},
      {5, "paraguas", %{}, {"1", "un"}, :one, 1, {"1 paraguas", "un paraguas"}, :full},
      {6, "paraguas", %{}, {"2", "dos"}, :other, 2, {"2 paraguas", "dos paraguas"}, :full}
    ],
    fr: [
      {1, "homme", %{}, {"1", "un"}, :one, 1, {"1 homme", "un homme"}, :full},
      {2, "homme", %{}, {"2", "deux"}, :other, 2, {"2 hommes", "deux hommes"}, :full},
      {3, "femme", %{}, {"1", "une"}, :one, 1, {"1 femme", "une femme"}, :full},
      {4, "femme", %{}, {"2", "deux"}, :other, 2, {"2 femmes", "deux femmes"}, :full}
    ],
    pt: [
      {1, "homem", %{}, {"1", "um"}, :one, 1, {"1 homem", "um homem"}, :full},
      {2, "homem", %{}, {"2", "dois"}, :other, 2, {"2 homens", "dois homens"}, :full},
      {3, "mulheraça", %{}, {"1", "uma"}, :one, 1, {"1 mulheraça", "uma mulheraça"}, :full},
      {4, "mulheraça", %{}, {"2", "duas"}, :other, 2, {"2 mulheraças", "duas mulheraças"}, :full}
    ],
    da: [
      {1, "kvinde", %{}, {"1", "en"}, :one, 1, {"1 kvinde", "en kvinde"}, :full},
      {2, "kvinde", %{}, {"2", "to"}, :other, 2, {"2 kvinder", "to kvinder"}, :full},
      {3, "lemma", %{}, {"1", "et"}, :one, 1, {"1 lemma", "et lemma"}, :full},
      {4, "lemma", %{}, {"2", "to"}, :other, 2, {"2 lemmaer", "to lemmaer"}, :full}
    ],
    sv: [
      {1, "kvinna", %{}, {"1", "en"}, :one, 1, {"1 kvinna", "en kvinna"}, :full},
      {2, "kvinna", %{}, {"2", "två"}, :other, 2, {"2 kvinnor", "två kvinnor"}, :full},
      {3, "lemma", %{}, {"1", "ett"}, :one, 1, {"1 lemma", "ett lemma"}, :full},
      {4, "lemma", %{}, {"2", "två"}, :other, 2, {"2 lemman", "två lemman"}, :full}
    ],
    nb: [
      {1, "mann", %{}, {"1", "én"}, :one, 1, {"1 mann", "én mann"}, :full},
      {2, "mann", %{}, {"2", "to"}, :other, 2, {"2 menn", "to menn"}, :full},
      {3, "bildøra", %{}, {"1", "ei"}, :one, 1, {"1 bildøra", "ei bildøra"}, :full},
      {4, "bildøra", %{}, {"2", "to"}, :other, 2, {"2 bildørene", "to bildørene"}, :full},
      {5, "bokmerke", %{}, {"1", "ett"}, :one, 1, {"1 bokmerke", "ett bokmerke"}, :full},
      {6, "bokmerke", %{}, {"2", "to"}, :other, 2, {"2 bokmerker", "to bokmerker"}, :full},
      {7, "budskap", %{}, {"1", "ett"}, :one, 1, {"1 budskap", "ett budskap"}, :full},
      {8, "budskap", %{}, {"2", "to"}, :other, 2, {"2 budskap", "to budskap"}, :full}
    ],
    de: [
      {1, "Kind", %{}, {"1", "ein"}, :one, 1, {"1 Kind", "ein Kind"}, :full},
      {2, "Kind", %{}, {"2", "zwei"}, :other, 2, {"2 Kinder", "zwei Kinder"}, :full},
      {3, "Kind", %{"case" => "genitive"}, {"1", "eines"}, :one, 1, {"1 Kindes", "eines Kindes"},
       :full},
      {4, "Kind", %{"case" => "genitive"}, {"2", "zwei"}, :other, 2, {"2 Kinder", "zwei Kinder"},
       :full},
      {5, "Kind", %{"case" => "dative"}, {"1", "einem"}, :one, 1, {"1 Kind", "einem Kind"},
       :full},
      {6, "Kind", %{"case" => "dative"}, {"2", "zwei"}, :other, 2, {"2 Kindern", "zwei Kindern"},
       :full},
      {7, "Kind", %{"case" => "accusative"}, {"1", "ein"}, :one, 1, {"1 Kind", "ein Kind"},
       :full},
      {8, "Kind", %{"case" => "accusative"}, {"2", "zwei"}, :other, 2,
       {"2 Kinder", "zwei Kinder"}, :full},
      {9, "Film", %{}, {"1", "ein"}, :one, 1, {"1 Film", "ein Film"}, :full},
      {10, "Film", %{}, {"2", "zwei"}, :other, 2, {"2 Filme", "zwei Filme"}, :full},
      {11, "Film", %{"case" => "genitive"}, {"1", "eines"}, :one, 1, {"1 Filmes", "eines Filmes"},
       :full},
      {12, "Film", %{"case" => "genitive"}, {"2", "zwei"}, :other, 2, {"2 Filme", "zwei Filme"},
       :full},
      {13, "Film", %{"case" => "dative"}, {"1", "einem"}, :one, 1, {"1 Film", "einem Film"},
       :full},
      {14, "Film", %{"case" => "dative"}, {"2", "zwei"}, :other, 2, {"2 Filmen", "zwei Filmen"},
       :full},
      {15, "Film", %{"case" => "accusative"}, {"1", "einen"}, :one, 1, {"1 Film", "einen Film"},
       :full},
      {16, "Film", %{"case" => "accusative"}, {"2", "zwei"}, :other, 2, {"2 Filme", "zwei Filme"},
       :full},
      {17, "Antwort", %{}, {"1", "eine"}, :one, 1, {"1 Antwort", "eine Antwort"}, :full},
      {18, "Antwort", %{}, {"2", "zwei"}, :other, 2, {"2 Antworten", "zwei Antworten"}, :full},
      {19, "Antwort", %{"case" => "genitive"}, {"1", "einer"}, :one, 1,
       {"1 Antwort", "einer Antwort"}, :full},
      {20, "Antwort", %{"case" => "genitive"}, {"2", "zwei"}, :other, 2,
       {"2 Antworten", "zwei Antworten"}, :full},
      {21, "Antwort", %{"case" => "dative"}, {"1", "einer"}, :one, 1,
       {"1 Antwort", "einer Antwort"}, :full},
      {22, "Antwort", %{"case" => "dative"}, {"2", "zwei"}, :other, 2,
       {"2 Antworten", "zwei Antworten"}, :full},
      {23, "Antwort", %{"case" => "accusative"}, {"1", "eine"}, :one, 1,
       {"1 Antwort", "eine Antwort"}, :full},
      {24, "Antwort", %{"case" => "accusative"}, {"2", "zwei"}, :other, 2,
       {"2 Antworten", "zwei Antworten"}, :full}
    ],
    fi: [
      {1, "viesti", %{}, {"1", "yksi"}, :one, 1, {"1 viesti", "yksi viesti"}, :full},
      {2, "viesti", %{}, {"2", "kaksi"}, :other, 2, {"2 viestiä", "kaksi viestiä"}, :full},
      {3, "viesti", %{"case" => "nominative"}, {"1", "yksi"}, :one, 1,
       {"1 viesti", "yksi viesti"}, :full},
      {4, "viesti", %{"case" => "nominative"}, {"2", "kaksi"}, :other, 2,
       {"2 viestiä", "kaksi viestiä"}, :full},
      {5, "viesti", %{"case" => "partitive"}, {"1", "yhtä"}, :one, 1,
       {"1 viestiä", "yhtä viestiä"}, :full},
      {6, "viesti", %{"case" => "genitive"}, {"1", "yhden"}, :one, 1,
       {"1 viestin", "yhden viestin"}, :full},
      {7, "viesti", %{"case" => "inessive"}, {"1", "yhdessä"}, :one, 1,
       {"1 viestissä", "yhdessä viestissä"}, :full},
      {8, "viesti", %{"case" => "elative"}, {"1", "yhdestä"}, :one, 1,
       {"1 viestistä", "yhdestä viestistä"}, :full},
      {9, "viesti", %{"case" => "illative"}, {"1", "yhteen"}, :one, 1,
       {"1 viestiin", "yhteen viestiin"}, :full},
      {10, "viesti", %{"case" => "adessive"}, {"1", "yhdellä"}, :one, 1,
       {"1 viestillä", "yhdellä viestillä"}, :full},
      {11, "viesti", %{"case" => "ablative"}, {"1", "yhdeltä"}, :one, 1,
       {"1 viestiltä", "yhdeltä viestiltä"}, :full},
      {12, "viesti", %{"case" => "allative"}, {"1", "yhdelle"}, :one, 1,
       {"1 viestille", "yhdelle viestille"}, :full},
      {13, "viesti", %{"case" => "essive"}, {"1", "yhtenä"}, :one, 1,
       {"1 viestinä", "yhtenä viestinä"}, :full},
      {14, "viesti", %{"case" => "translative"}, {"1", "yhdeksi"}, :one, 1,
       {"1 viestiksi", "yhdeksi viestiksi"}, :full},
      {15, "viesti", %{"case" => "partitive"}, {"2", "kahta"}, :other, 2,
       {"2 viestiä", "kahta viestiä"}, :full},
      {16, "viesti", %{"case" => "genitive"}, {"2", "kahden"}, :other, 2,
       {"2 viestin", "kahden viestin"}, :full},
      {17, "viesti", %{"case" => "inessive"}, {"2", "kahdessa"}, :other, 2,
       {"2 viestissä", "kahdessa viestissä"}, :full},
      {18, "viesti", %{"case" => "elative"}, {"2", "kahdesta"}, :other, 2,
       {"2 viestistä", "kahdesta viestistä"}, :full},
      {19, "viesti", %{"case" => "illative"}, {"2", "kahteen"}, :other, 2,
       {"2 viestiin", "kahteen viestiin"}, :full},
      {20, "viesti", %{"case" => "adessive"}, {"2", "kahdella"}, :other, 2,
       {"2 viestillä", "kahdella viestillä"}, :full},
      {21, "viesti", %{"case" => "ablative"}, {"2", "kahdelta"}, :other, 2,
       {"2 viestiltä", "kahdelta viestiltä"}, :full},
      {22, "viesti", %{"case" => "allative"}, {"2", "kahdelle"}, :other, 2,
       {"2 viestille", "kahdelle viestille"}, :full},
      {23, "viesti", %{"case" => "essive"}, {"2", "kahtena"}, :other, 2,
       {"2 viestinä", "kahtena viestinä"}, :full},
      {24, "viesti", %{"case" => "translative"}, {"2", "kahdeksi"}, :other, 2,
       {"2 viestiksi", "kahdeksi viestiksi"}, :full},
      {25, "häät", %{}, {"1", "yhdet"}, :one, 1, {"1 häät", "yhdet häät"}, :full},
      {26, "häät", %{}, {"2", "kahdet"}, :other, 2, {"2 häät", "kahdet häät"}, :full},
      {27, "häät", %{"case" => "inessive"}, {"1", "yksissä"}, :one, 1,
       {"1 häissä", "yksissä häissä"}, :full},
      {28, "häät", %{"case" => "inessive"}, {"2", "kaksissa"}, :other, 2,
       {"2 häissä", "kaksissa häissä"}, :full},
      {29, "häät", %{"case" => "genitive"}, {"1", "yksien"}, :one, 1,
       {"1 häiden", "yksien häiden"}, :full},
      {30, "häät", %{"case" => "genitive"}, {"2", "kaksien"}, :other, 2,
       {"2 häiden", "kaksien häiden"}, :full},
      {31, "kisa", %{"case" => "genitive"}, {"1", "yhden"}, :one, 1, {"1 kisan", "yhden kisan"},
       :full},
      {32, "kisa", %{"case" => "genitive"}, {"2", "kahden"}, :other, 2,
       {"2 kisan", "kahden kisan"}, :full},
      {33, "kisa", %{"case" => "genitive", "number" => "plural"}, {"1", "yksien"}, :one, 1,
       {"1 kisojen", "yksien kisojen"}, :full},
      {34, "kisa", %{"case" => "genitive", "number" => "plural"}, {"2", "kaksien"}, :other, 2,
       {"2 kisojen", "kaksien kisojen"}, :full}
    ],
    ru: [
      {1, "карандаш", %{}, {"1", "один"}, :one, 1, {"1 карандаш", "один карандаш"}, :full},
      {2, "карандаш", %{}, {"2", "два"}, :few, 2, {"2 карандаша", "два карандаша"}, :full},
      {3, "карандаш", %{}, {"5", "пять"}, :many, 5, {"5 карандашей", "пять карандашей"}, :full},
      {4, "женщина", %{}, {"1", "одна"}, :one, 1, {"1 женщина", "одна женщина"}, :full},
      {5, "женщина", %{}, {"2", "две"}, :few, 2, {"2 женщины", "две женщины"}, :full},
      {6, "женщина", %{}, {"5", "пять"}, :many, 5, {"5 женщин", "пять женщин"}, :full},
      {7, "сообщение", %{}, {"1", "одно"}, :one, 1, {"1 сообщение", "одно сообщение"}, :full},
      {8, "сообщение", %{}, {"2", "два"}, :few, 2, {"2 сообщения", "два сообщения"}, :full},
      {9, "сообщение", %{}, {"5", "пять"}, :many, 5, {"5 сообщений", "пять сообщений"}, :full},
      {10, "стол", %{}, {"1", "один"}, :one, 1, {"1 стол", "один стол"}, :full},
      {11, "стол", %{}, {"2", "два"}, :few, 2, {"2 стола", "два стола"}, :full},
      {12, "стол", %{}, {"5", "пять"}, :many, 5, {"5 столов", "пять столов"}, :full},
      {13, "стол", %{"case" => "genitive"}, {"1", "одного"}, :one, 1, {"1 стола", "одного стола"},
       :full},
      {14, "стол", %{"case" => "genitive"}, {"2", "двух"}, :few, 2, {"2 столов", "двух столов"},
       :full},
      {15, "стол", %{"case" => "genitive"}, {"5", "пяти"}, :many, 5, {"5 столов", "пяти столов"},
       :full},
      {16, "стол", %{"case" => "accusative"}, {"1", "один"}, :one, 1, {"1 стол", "один стол"},
       :full},
      {17, "стол", %{"case" => "accusative"}, {"2", "два"}, :few, 2, {"2 стола", "два стола"},
       :full},
      {18, "стол", %{"case" => "accusative"}, {"5", "пять"}, :many, 5,
       {"5 столов", "пять столов"}, :full},
      {19, "стол", %{"case" => "dative"}, {"1", "одному"}, :one, 1, {"1 столу", "одному столу"},
       :full},
      {20, "стол", %{"case" => "dative"}, {"2", "двум"}, :few, 2, {"2 столам", "двум столам"},
       :full},
      {21, "стол", %{"case" => "dative"}, {"5", "пяти"}, :many, 5, {"5 столам", "пяти столам"},
       :full},
      {22, "стол", %{"case" => "instrumental"}, {"1", "одним"}, :one, 1,
       {"1 столом", "одним столом"}, :full},
      {23, "стол", %{"case" => "instrumental"}, {"2", "двумя"}, :few, 2,
       {"2 столами", "двумя столами"}, :full},
      {24, "стол", %{"case" => "instrumental"}, {"5", "пятью"}, :many, 5,
       {"5 столами", "пятью столами"}, :full},
      {25, "стол", %{"case" => "prepositional"}, {"1", "одном"}, :one, 1,
       {"1 столе", "одном столе"}, :full},
      {26, "стол", %{"case" => "prepositional"}, {"2", "двух"}, :few, 2,
       {"2 столах", "двух столах"}, :full},
      {27, "стол", %{"case" => "prepositional"}, {"5", "пяти"}, :many, 5,
       {"5 столах", "пяти столах"}, :full},
      {28, "сантиметр", %{}, {"1,25", "одна целая двадцать пять сотых"}, :other, 1.25,
       {"1,25 сантиметра", "одна целая двадцать пять сотых сантиметра"}, :full},
      {29, "сантиметр", %{}, {"2,25", "две целых двадцать пять сотых"}, :other, 2.25,
       {"2,25 сантиметра", "две целых двадцать пять сотых сантиметра"}, :full},
      {30, "сантиметр", %{}, {"5,25", "пять целых двадцать пять сотых"}, :other, 5.25,
       {"5,25 сантиметра", "пять целых двадцать пять сотых сантиметра"}, :full},
      {31, "QQQ", %{}, "1,25", :other, 1.25, "1,25 QQQ", :full},
      {32, "QQQ", %{}, "2", :few, 2, "2 QQQ", :full},
      {33, "стол", %{"case" => "ablative"}, {"1", "одним"}, :one, 1, {"1 столом", "одним столом"},
       :full},
      {34, "стол", %{"case" => "ablative"}, {"2", "двумя"}, :few, 2,
       {"2 столами", "двумя столами"}, :full},
      {35, "стол", %{"case" => "ablative"}, {"5", "пятью"}, :many, 5,
       {"5 столами", "пятью столами"}, :full},
      {36, "стол", %{"case" => "locative"}, {"1", "одном"}, :one, 1, {"1 столе", "одном столе"},
       :full},
      {37, "стол", %{"case" => "locative"}, {"2", "двух"}, :few, 2, {"2 столах", "двух столах"},
       :full},
      {38, "стол", %{"case" => "locative"}, {"5", "пяти"}, :many, 5, {"5 столах", "пяти столах"},
       :full}
    ],
    pl: [
      {1, "lekarz", %{}, {"1", "jeden"}, :one, 1, {"1 lekarz", "jeden lekarz"}, :full},
      {2, "lekarz", %{}, {"2", "dwaj"}, :few, 2, {"2 lekarze", "dwaj lekarze"}, :full},
      {3, "lekarz", %{}, {"5", "pięciu"}, :many, 5, {"5 lekarzy", "pięciu lekarzy"}, :full},
      {4, "kilometr", %{}, {"1", "jeden"}, :one, 1, {"1 kilometr", "jeden kilometr"}, :full},
      {5, "kilometr", %{}, {"2", "dwa"}, :few, 2, {"2 kilometry", "dwa kilometry"}, :full},
      {6, "kilometr", %{}, {"5", "pięć"}, :many, 5, {"5 kilometrów", "pięć kilometrów"}, :full},
      {7, "lampa", %{}, {"1", "jedna"}, :one, 1, {"1 lampa", "jedna lampa"}, :full},
      {8, "lampa", %{}, {"2", "dwie"}, :few, 2, {"2 lampy", "dwie lampy"}, :full},
      {9, "lampa", %{}, {"5", "pięć"}, :many, 5, {"5 lamp", "pięć lamp"}, :full},
      {10, "światło", %{}, {"1", "jedno"}, :one, 1, {"1 światło", "jedno światło"}, :full},
      {11, "światło", %{}, {"2", "dwa"}, :few, 2, {"2 światła", "dwa światła"}, :full},
      {12, "światło", %{}, {"5", "pięć"}, :many, 5, {"5 świateł", "pięć świateł"}, :full},
      {13, "lekarz", %{"case" => "genitive"}, {"1", "jednego"}, :one, 1,
       {"1 lekarza", "jednego lekarza"}, :full},
      {14, "lekarz", %{"case" => "genitive"}, {"2", "dwóch"}, :few, 2,
       {"2 lekarzy", "dwóch lekarzy"}, :full},
      {15, "lekarz", %{"case" => "genitive"}, {"5", "pięciu"}, :many, 5,
       {"5 lekarzy", "pięciu lekarzy"}, :full},
      {16, "lekarz", %{"case" => "accusative"}, {"1", "jednego"}, :one, 1,
       {"1 lekarza", "jednego lekarza"}, :full},
      {17, "lekarz", %{"case" => "accusative"}, {"2", "dwóch"}, :few, 2,
       {"2 lekarzy", "dwóch lekarzy"}, :full},
      {18, "lekarz", %{"case" => "accusative"}, {"5", "pięciu"}, :many, 5,
       {"5 lekarzy", "pięciu lekarzy"}, :full},
      {19, "byk", %{"case" => "accusative"}, {"1", "jednego"}, :one, 1,
       {"1 byka", "jednego byka"}, :full},
      {20, "byk", %{"case" => "accusative"}, {"2", "dwa"}, :few, 2, {"2 byki", "dwa byki"},
       :full},
      {21, "byk", %{"case" => "accusative"}, {"5", "pięć"}, :many, 5, {"5 byków", "pięć byków"},
       :full},
      {22, "kilometr", %{"case" => "accusative"}, {"1", "jeden"}, :one, 1,
       {"1 kilometr", "jeden kilometr"}, :full},
      {23, "kilometr", %{"case" => "accusative"}, {"2", "dwa"}, :few, 2,
       {"2 kilometry", "dwa kilometry"}, :full},
      {24, "kilometr", %{"case" => "accusative"}, {"5", "pięć"}, :many, 5,
       {"5 kilometrów", "pięć kilometrów"}, :full},
      {25, "lampa", %{"case" => "accusative"}, {"1", "jedną"}, :one, 1,
       {"1 lampę", "jedną lampę"}, :full},
      {26, "lampa", %{"case" => "accusative"}, {"2", "dwie"}, :few, 2, {"2 lampy", "dwie lampy"},
       :full},
      {27, "lampa", %{"case" => "accusative"}, {"5", "pięć"}, :many, 5, {"5 lamp", "pięć lamp"},
       :full},
      {28, "światło", %{"case" => "accusative"}, {"1", "jedno"}, :one, 1,
       {"1 światło", "jedno światło"}, :full},
      {29, "światło", %{"case" => "accusative"}, {"2", "dwa"}, :few, 2,
       {"2 światła", "dwa światła"}, :full},
      {30, "światło", %{"case" => "accusative"}, {"5", "pięć"}, :many, 5,
       {"5 świateł", "pięć świateł"}, :full},
      {31, "lekarz", %{"case" => "dative"}, {"1", "jednemu"}, :one, 1,
       {"1 lekarzowi", "jednemu lekarzowi"}, :full},
      {32, "lekarz", %{"case" => "dative"}, {"2", "dwóm"}, :few, 2,
       {"2 lekarzom", "dwóm lekarzom"}, :full},
      {33, "lekarz", %{"case" => "dative"}, {"5", "pięciu"}, :many, 5,
       {"5 lekarzom", "pięciu lekarzom"}, :full},
      {34, "lekarz", %{"case" => "instrumental"}, {"1", "jednym"}, :one, 1,
       {"1 lekarzem", "jednym lekarzem"}, :full},
      {35, "lekarz", %{"case" => "instrumental"}, {"2", "dwoma"}, :few, 2,
       {"2 lekarzami", "dwoma lekarzami"}, :full},
      {36, "lekarz", %{"case" => "instrumental"}, {"5", "pięcioma"}, :many, 5,
       {"5 lekarzami", "pięcioma lekarzami"}, :full},
      {37, "lekarz", %{"case" => "locative"}, {"1", "jednym"}, :one, 1,
       {"1 lekarzu", "jednym lekarzu"}, :full},
      {38, "lekarz", %{"case" => "locative"}, {"2", "dwóch"}, :few, 2,
       {"2 lekarzach", "dwóch lekarzach"}, :full},
      {39, "lekarz", %{"case" => "locative"}, {"5", "pięciu"}, :many, 5,
       {"5 lekarzach", "pięciu lekarzach"}, :full},
      {40, "kilometr", %{}, {"1,25", "jeden przecinek dwadzieścia pięć"}, :other, 1.25,
       {"1,25 kilometra", "jeden przecinek dwadzieścia pięć kilometra"}, :full},
      {41, "kilometr", %{}, {"2,25", "dwa przecinek dwadzieścia pięć"}, :other, 2.25,
       {"2,25 kilometra", "dwa przecinek dwadzieścia pięć kilometra"}, :full},
      {42, "kilometr", %{}, {"5,25", "pięć przecinek dwadzieścia pięć"}, :other, 5.25,
       {"5,25 kilometra", "pięć przecinek dwadzieścia pięć kilometra"}, :full},
      {43, "QQQ", %{}, "1,25", :other, 1.25, "1,25 QQQ", :full},
      {44, "QQQ", %{}, "2", :few, 2, "2 QQQ", :full}
    ],
    ja: [
      {1, "word", %{}, "1", :other, 1, "1word", :full},
      {2, "Word", %{"measure" => "Blah"}, "2", :other, 2, "2BlahWord", :full}
    ],
    zh: [
      {1, "word", %{}, "1", :other, 1, "1word", :full},
      {2, "Word", %{"measure" => "Blah"}, "2", :other, 2, "2BlahWord", :full}
    ],
    yue: [
      {1, "word", %{}, "1", :other, 1, "1word", :full},
      {2, "Word", %{"measure" => "Blah"}, "2", :other, 2, "2BlahWord", :full}
    ],
    ml: [
      {1, "പുസ്തകം", %{}, "1", :one, 1, "പുസ്തകം 1", :full},
      {2, "പുസ്തകം", %{}, "2", :other, 2, "2 പുസ്തകങ്ങളെ", :full}
    ],
    sr: [
      {1, "брод", %{}, {"1", "један"}, :one, 1, {"1 брод", "један брод"}, :full},
      {2, "брод", %{}, {"2", "два"}, :few, 2, {"2 брода", "два брода"}, :full},
      {3, "брод", %{}, {"3", "три"}, :few, 3, {"3 брода", "три брода"}, :full},
      {4, "брод", %{}, {"4", "четири"}, :few, 4, {"4 брода", "четири брода"}, :full},
      {5, "брод", %{}, {"5", "пет"}, :other, 5, {"5 бродова", "пет бродова"}, :full},
      {6, "брод", %{}, {"1,1", "један зарез један"}, :one, 1.1,
       {"1,1 брода", "један зарез један брода"}, :full},
      {7, "земља", %{}, {"1", "једна"}, :one, 1, {"1 земља", "једна земља"}, :full},
      {8, "земља", %{}, {"2", "две"}, :few, 2, {"2 земље", "две земље"}, :full},
      {9, "земља", %{}, {"5", "пет"}, :other, 5, {"5 земаља", "пет земаља"}, :full},
      {10, "земља", %{}, {"1,1", "једна зарез једна"}, :one, 1.1,
       {"1,1 земље", "једна зарез једна земље"}, :full},
      {11, "брод", %{"case" => "locative"}, {"5", "пет"}, :other, 5, {"5 бродова", "пет бродова"},
       :full},
      {12, "брод", %{"case" => "instrumental"}, {"5", "пет"}, :other, 5,
       {"5 бродова", "пет бродова"}, :full},
      {13, "брод", %{"case" => "dative"}, {"5", "пет"}, :other, 5, {"5 бродова", "пет бродова"},
       :full},
      {14, "земља", %{"case" => "locative"}, {"5", "пет"}, :other, 5, {"5 земаља", "пет земаља"},
       :full},
      {15, "земља", %{"case" => "instrumental"}, {"5", "пет"}, :other, 5,
       {"5 земаља", "пет земаља"}, :full}
    ]
  }

  for {locale, rows} <- @cases do
    test "upstream #{locale} quantify expectations" do
      locale = unquote(locale)

      failures =
        unquote(Macro.escape(rows))
        |> Enum.map(fn {index, string, _, _, _, _, _, _} = row ->
          case run_case(locale, row) do
            nil -> nil
            description -> "##{index} #{string}: #{description}"
          end
        end)
        |> Enum.reject(&is_nil/1)

      assert failures == []
    end
  end

  defp run_case(
         locale,
         {_index, string, constraints, formatted, category, number, expected, mode}
       ) do
    case quantify(locale, string, constraints, formatted, category, number) do
      {:ok, got} -> compare(got, expected, mode)
      {:error, reason} -> "error: #{inspect(reason)}"
    end
  end

  defp quantify(locale, string, constraints, formatted, category, number) do
    with {:ok, concept} <- Concept.new(locale, string, constraints: constraints) do
      Quantify.quantify_formatted(locale, formatted, concept, plural: category, number: number)
    end
  end

  defp compare(got, expected, :full) do
    if got == expected do
      nil
    else
      "got #{inspect(got)}, want #{inspect(expected)}"
    end
  end

  defp compare(got, expected, :print) do
    print = SpeakableString.print(got)

    if print == expected do
      nil
    else
      "got print #{inspect(print)}, want print #{inspect(expected)}"
    end
  end
end
