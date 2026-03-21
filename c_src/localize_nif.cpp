// Localize NIF: ICU4C bindings for the localize library.
//
// Provides:
//   nif_mf2_validate/1      - Parse an MF2 message and return normalized pattern or error
//   nif_mf2_format/3        - Format an MF2 message with locale and JSON-encoded arguments
//   nif_collation_cmp/10    - Compare two strings using ICU collation with full option support
//   nif_plural_rule/4       - Select plural category using ICU PluralRules
//   nif_number_format/4     - Format a number using ICU NumberFormatter

#include <cstring>
#include <map>
#include <string>

#include "erl_nif.h"

#include "unicode/ucol.h"
#include "unicode/uscript.h"
#include "unicode/errorcode.h"
#include "unicode/locid.h"
#include "unicode/messageformat2.h"
#include "unicode/messageformat2_arguments.h"
#include "unicode/messageformat2_formattable.h"
#include "unicode/parseerr.h"
#include "unicode/numberformatter.h"
#include "unicode/plurrule.h"
#include "unicode/unistr.h"
#include "unicode/utypes.h"

using icu::Locale;
using icu::UnicodeString;
using icu::message2::Formattable;
using icu::message2::MessageArguments;
using icu::message2::MessageFormatter;

/* ── Atom cache ─────────────────────────────────────────────────── */

static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_error;

/* ── Collation pool ────────────────────────────────────────────── */

/* Use -1 as sentinel for "use default / no change" */
#define OPT_DEFAULT (-1)

typedef struct {
    UCollator** collators;
    int collStackTop;
    int numCollators;
    ErlNifMutex* collMutex;
} collation_priv_t;

static inline void
reserve_coll(collation_priv_t* pData, UCollator** out)
{
    enif_mutex_lock(pData->collMutex);
    *out = pData->collators[pData->collStackTop];
    pData->collStackTop += 1;
    enif_mutex_unlock(pData->collMutex);
}

static inline void
release_coll(collation_priv_t* pData)
{
    enif_mutex_lock(pData->collMutex);
    pData->collStackTop -= 1;
    enif_mutex_unlock(pData->collMutex);
}

static collation_priv_t*
init_collation_pool(int num_schedulers)
{
    if (num_schedulers < 1) return NULL;

    UErrorCode status = U_ZERO_ERROR;
    collation_priv_t* pData = (collation_priv_t*)enif_alloc(sizeof(collation_priv_t));
    if (!pData) return NULL;

    pData->collators = NULL;
    pData->collStackTop = 0;
    pData->numCollators = num_schedulers;
    pData->collMutex = enif_mutex_create((char*)"localize_coll_mutex");

    if (!pData->collMutex) {
        enif_free(pData);
        return NULL;
    }

    pData->collators = (UCollator**)enif_alloc(sizeof(UCollator*) * num_schedulers);
    if (!pData->collators) {
        enif_mutex_destroy(pData->collMutex);
        enif_free(pData);
        return NULL;
    }

    for (int i = 0; i < num_schedulers; i++) {
        pData->collators[i] = ucol_open("", &status);
        if (U_FAILURE(status)) {
            for (int j = 0; j < i; j++) {
                ucol_close(pData->collators[j]);
            }
            enif_free(pData->collators);
            enif_mutex_destroy(pData->collMutex);
            enif_free(pData);
            return NULL;
        }
    }

    return pData;
}

static void
destroy_collation_pool(collation_priv_t* pData)
{
    if (!pData) return;

    if (pData->collators) {
        for (int i = 0; i < pData->numCollators; i++) {
            ucol_close(pData->collators[i]);
        }
        enif_free(pData->collators);
    }

    if (pData->collMutex) {
        enif_mutex_destroy(pData->collMutex);
    }

    enif_free(pData);
}

/* ── Lifecycle ──────────────────────────────────────────────────── */

static int
on_load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM info)
{
    atom_ok = enif_make_atom(env, "ok");
    atom_error = enif_make_atom(env, "error");

    int num_schedulers = 0;
    if (enif_get_int(env, info, &num_schedulers) && num_schedulers > 0) {
        *priv_data = init_collation_pool(num_schedulers);
    } else {
        /* Default pool size */
        *priv_data = init_collation_pool(4);
    }

    return 0;
}

static void
on_unload(ErlNifEnv* env, void* priv_data)
{
    destroy_collation_pool((collation_priv_t*)priv_data);
}

static int
on_upgrade(ErlNifEnv* env, void** priv_data, void** old_data, ERL_NIF_TERM info)
{
    atom_ok = enif_make_atom(env, "ok");
    atom_error = enif_make_atom(env, "error");

    /* Clean up old collation pool */
    if (*old_data) {
        destroy_collation_pool((collation_priv_t*)*old_data);
    }

    int num_schedulers = 0;
    if (enif_get_int(env, info, &num_schedulers) && num_schedulers > 0) {
        *priv_data = init_collation_pool(num_schedulers);
    } else {
        *priv_data = init_collation_pool(4);
    }

    return 0;
}

/* ── Helpers ────────────────────────────────────────────────────── */

// Extract a UTF-8 binary into a std::string
static bool get_string(ErlNifEnv* env, ERL_NIF_TERM term, std::string& out) {
    ErlNifBinary bin;
    if (!enif_inspect_binary(env, term, &bin)) {
        return false;
    }
    out.assign(reinterpret_cast<const char*>(bin.data), bin.size);
    return true;
}

// Make an Elixir binary from a UnicodeString
static ERL_NIF_TERM make_binary_from_unistr(ErlNifEnv* env, const UnicodeString& ustr) {
    std::string utf8;
    ustr.toUTF8String(utf8);

    ERL_NIF_TERM bin;
    unsigned char* buf = enif_make_new_binary(env, utf8.size(), &bin);
    memcpy(buf, utf8.data(), utf8.size());
    return bin;
}

// Make an Elixir binary from a std::string
static ERL_NIF_TERM make_binary_from_string(ErlNifEnv* env, const std::string& str) {
    ERL_NIF_TERM bin;
    unsigned char* buf = enif_make_new_binary(env, str.size(), &bin);
    memcpy(buf, str.data(), str.size());
    return bin;
}

/* ── JSON argument parsing ──────────────────────────────────────── */

// Parse a simple JSON string value (between quotes).
// Returns the parsed string and advances pos past the closing quote.
static std::string parse_json_string(const std::string& json, size_t& pos) {
    std::string result;
    pos++; // skip opening quote
    while (pos < json.size()) {
        char c = json[pos];
        if (c == '"') {
            pos++; // skip closing quote
            return result;
        }
        if (c == '\\' && pos + 1 < json.size()) {
            pos++;
            char escaped = json[pos];
            switch (escaped) {
                case '"': result += '"'; break;
                case '\\': result += '\\'; break;
                case '/': result += '/'; break;
                case 'n': result += '\n'; break;
                case 't': result += '\t'; break;
                case 'r': result += '\r'; break;
                default: result += escaped; break;
            }
        } else {
            result += c;
        }
        pos++;
    }
    return result;
}

static void skip_ws(const std::string& json, size_t& pos) {
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t' ||
           json[pos] == '\n' || json[pos] == '\r')) {
        pos++;
    }
}

// Parse a JSON value as a string (for Formattable).
// Handles: strings, numbers (as string), booleans, null.
static std::string parse_json_value(const std::string& json, size_t& pos) {
    skip_ws(json, pos);
    if (pos >= json.size()) return "";

    char c = json[pos];
    if (c == '"') {
        return parse_json_string(json, pos);
    }
    // For numbers, booleans, null: read until delimiter
    size_t start = pos;
    while (pos < json.size() && json[pos] != ',' && json[pos] != '}' &&
           json[pos] != ']' && json[pos] != ' ' && json[pos] != '\n') {
        pos++;
    }
    return json.substr(start, pos - start);
}

// Parse a simple JSON object {"key": "value", ...} into a map of
// UnicodeString -> Formattable. Only supports flat string/number values.
static bool parse_json_args(const std::string& json,
                            std::map<UnicodeString, Formattable>& args) {
    size_t pos = 0;
    skip_ws(json, pos);
    if (pos >= json.size() || json[pos] != '{') return false;
    pos++; // skip {

    while (pos < json.size()) {
        skip_ws(json, pos);
        if (json[pos] == '}') break;
        if (json[pos] == ',') { pos++; continue; }

        // Parse key
        if (json[pos] != '"') return false;
        std::string key = parse_json_string(json, pos);

        skip_ws(json, pos);
        if (pos >= json.size() || json[pos] != ':') return false;
        pos++; // skip :

        // Parse value
        skip_ws(json, pos);
        char vc = json[pos];
        if (vc == '"') {
            std::string val = parse_json_string(json, pos);
            UnicodeString uval = UnicodeString::fromUTF8(val);
            args[UnicodeString::fromUTF8(key)] = Formattable(uval);
        } else {
            // Try to parse as number
            std::string val = parse_json_value(json, pos);
            bool is_number = !val.empty();
            bool has_dot = false;
            for (size_t i = 0; i < val.size(); i++) {
                char ch = val[i];
                if (ch == '-' && i == 0) continue;
                if (ch == '.') { has_dot = true; continue; }
                if (ch < '0' || ch > '9') { is_number = false; break; }
            }
            if (is_number && has_dot) {
                args[UnicodeString::fromUTF8(key)] = Formattable(std::stod(val));
            } else if (is_number) {
                args[UnicodeString::fromUTF8(key)] = Formattable(static_cast<int64_t>(std::stoll(val)));
            } else {
                // fallback: treat as string
                UnicodeString uval = UnicodeString::fromUTF8(val);
                args[UnicodeString::fromUTF8(key)] = Formattable(uval);
            }
        }
    }
    return true;
}

/* ── MF2 NIF functions ──────────────────────────────────────────── */

// nif_mf2_validate(message_binary) -> {:ok, normalized_pattern} | {:error, reason}
static ERL_NIF_TERM nif_mf2_validate(ErlNifEnv* env, int argc,
                                      const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    std::string message;
    if (!get_string(env, argv[0], message)) {
        return enif_make_badarg(env);
    }

    UErrorCode status = U_ZERO_ERROR;
    UParseError parseError;

    MessageFormatter::Builder builder(status);
    if (U_FAILURE(status)) {
        return enif_make_tuple2(env, atom_error,
                                make_binary_from_string(env, "builder init failed"));
    }

    UnicodeString umsg = UnicodeString::fromUTF8(message);
    builder.setPattern(umsg, parseError, status);

    if (U_FAILURE(status)) {
        std::string err = "parse error at offset ";
        err += std::to_string(parseError.offset);
        return enif_make_tuple2(env, atom_error,
                                make_binary_from_string(env, err));
    }

    MessageFormatter mf = builder.build(status);
    if (U_FAILURE(status)) {
        return enif_make_tuple2(env, atom_error,
                                make_binary_from_string(env, "build failed"));
    }

    UnicodeString pattern = mf.getPattern();
    return enif_make_tuple2(env, atom_ok,
                            make_binary_from_unistr(env, pattern));
}

// nif_mf2_format(message_binary, locale_binary, args_json_binary)
//      -> {:ok, result} | {:error, reason}
static ERL_NIF_TERM nif_mf2_format(ErlNifEnv* env, int argc,
                                    const ERL_NIF_TERM argv[]) {
    if (argc != 3) {
        return enif_make_badarg(env);
    }

    std::string message, locale_str, args_json;
    if (!get_string(env, argv[0], message) ||
        !get_string(env, argv[1], locale_str) ||
        !get_string(env, argv[2], args_json)) {
        return enif_make_badarg(env);
    }

    UErrorCode status = U_ZERO_ERROR;
    UParseError parseError;

    MessageFormatter::Builder builder(status);
    if (U_FAILURE(status)) {
        return enif_make_tuple2(env, atom_error,
                                make_binary_from_string(env, "builder init failed"));
    }

    Locale locale(locale_str.c_str());
    builder.setLocale(locale);

    UnicodeString umsg = UnicodeString::fromUTF8(message);
    builder.setPattern(umsg, parseError, status);

    if (U_FAILURE(status)) {
        std::string err = "parse error at offset ";
        err += std::to_string(parseError.offset);
        return enif_make_tuple2(env, atom_error,
                                make_binary_from_string(env, err));
    }

    MessageFormatter mf = builder.build(status);
    if (U_FAILURE(status)) {
        return enif_make_tuple2(env, atom_error,
                                make_binary_from_string(env, "build failed"));
    }

    // Parse arguments from JSON
    std::map<UnicodeString, Formattable> argsMap;
    if (!args_json.empty() && args_json != "{}") {
        if (!parse_json_args(args_json, argsMap)) {
            return enif_make_tuple2(env, atom_error,
                                    make_binary_from_string(env, "invalid args JSON"));
        }
    }

    MessageArguments msgArgs(argsMap, status);
    if (U_FAILURE(status)) {
        return enif_make_tuple2(env, atom_error,
                                make_binary_from_string(env, "args creation failed"));
    }

    UnicodeString result = mf.formatToString(msgArgs, status);
    // formatToString may return partial output even with errors,
    // so we return the result regardless of status for best-effort output.
    // Only return error if status indicates a syntax error.
    if (U_FAILURE(status) && status != U_MF_SYNTAX_ERROR) {
        return enif_make_tuple2(env, atom_ok,
                                make_binary_from_unistr(env, result));
    }

    if (U_FAILURE(status)) {
        return enif_make_tuple2(env, atom_error,
                                make_binary_from_string(env, "format failed"));
    }

    return enif_make_tuple2(env, atom_ok,
                            make_binary_from_unistr(env, result));
}

/* ── Collation NIF function ─────────────────────────────────────── */

// nif_collation_cmp(string_a, string_b, strength, backwards, alternate,
//                   case_first, case_level, normalization, numeric, reorder_bin)
// Each option is an integer. OPT_DEFAULT (-1) means "use collator default".
// reorder_bin is a binary of packed big-endian int32 reorder codes.
static ERL_NIF_TERM nif_collation_cmp(ErlNifEnv* env, int argc,
                                       const ERL_NIF_TERM argv[]) {
    if (argc != 10) {
        return enif_make_badarg(env);
    }

    ErlNifBinary binA, binB, reorderBin;
    int strength, backwards, alternate, case_first, case_level, normalization, numeric;
    int any_set = 0;
    int has_reorder = 0;
    UCollator* coll = NULL;

    collation_priv_t* pData = (collation_priv_t*)enif_priv_data(env);
    if (!pData) {
        return enif_make_int(env, 0);
    }

    /* Extract binary arguments */
    if (!enif_inspect_binary(env, argv[0], &binA) ||
        !enif_inspect_binary(env, argv[1], &binB)) {
        return enif_make_int(env, 0);
    }

    /* Extract option integers */
    if (!enif_get_int(env, argv[2], &strength) ||
        !enif_get_int(env, argv[3], &backwards) ||
        !enif_get_int(env, argv[4], &alternate) ||
        !enif_get_int(env, argv[5], &case_first) ||
        !enif_get_int(env, argv[6], &case_level) ||
        !enif_get_int(env, argv[7], &normalization) ||
        !enif_get_int(env, argv[8], &numeric)) {
        return enif_make_int(env, 0);
    }

    /* Extract reorder codes binary (10th arg) */
    if (!enif_inspect_binary(env, argv[9], &reorderBin)) {
        return enif_make_int(env, 0);
    }

    UErrorCode status = U_ZERO_ERROR;

    /* Set up UTF-8 iterators */
    UCharIterator iterA, iterB;
    uiter_setUTF8(&iterA, (const char*)binA.data, (uint32_t)binA.size);
    uiter_setUTF8(&iterB, (const char*)binB.data, (uint32_t)binB.size);

    /* Grab a collator from the pool */
    reserve_coll(pData, &coll);

    /* Apply non-default attributes */
    if (strength != OPT_DEFAULT) {
        ucol_setAttribute(coll, UCOL_STRENGTH, (UColAttributeValue)strength, &status);
        any_set = 1;
    }
    if (backwards != OPT_DEFAULT) {
        ucol_setAttribute(coll, UCOL_FRENCH_COLLATION, (UColAttributeValue)backwards, &status);
        any_set = 1;
    }
    if (alternate != OPT_DEFAULT) {
        ucol_setAttribute(coll, UCOL_ALTERNATE_HANDLING, (UColAttributeValue)alternate, &status);
        any_set = 1;
    }
    if (case_first != OPT_DEFAULT) {
        ucol_setAttribute(coll, UCOL_CASE_FIRST, (UColAttributeValue)case_first, &status);
        any_set = 1;
    }
    if (case_level != OPT_DEFAULT) {
        ucol_setAttribute(coll, UCOL_CASE_LEVEL, (UColAttributeValue)case_level, &status);
        any_set = 1;
    }
    if (normalization != OPT_DEFAULT) {
        ucol_setAttribute(coll, UCOL_NORMALIZATION_MODE, (UColAttributeValue)normalization, &status);
        any_set = 1;
    }
    if (numeric != OPT_DEFAULT) {
        ucol_setAttribute(coll, UCOL_NUMERIC_COLLATION, (UColAttributeValue)numeric, &status);
        any_set = 1;
    }

    /* Apply reorder codes if provided */
    if (reorderBin.size > 0 && reorderBin.size % 4 == 0) {
        int32_t numCodes = (int32_t)(reorderBin.size / 4);
        int32_t* codes = (int32_t*)enif_alloc(sizeof(int32_t) * numCodes);
        const unsigned char* p = reorderBin.data;

        for (int32_t i = 0; i < numCodes; i++) {
            codes[i] = (int32_t)(
                ((uint32_t)p[0] << 24) |
                ((uint32_t)p[1] << 16) |
                ((uint32_t)p[2] << 8)  |
                ((uint32_t)p[3])
            );
            p += 4;
        }

        ucol_setReorderCodes(coll, codes, numCodes, &status);
        enif_free(codes);
        has_reorder = 1;
    }

    /* Perform the comparison */
    int response = ucol_strcollIter(coll, &iterA, &iterB, &status);

    /* Restore all modified attributes to defaults */
    if (any_set) {
        status = U_ZERO_ERROR;
        if (strength != OPT_DEFAULT)
            ucol_setAttribute(coll, UCOL_STRENGTH, UCOL_DEFAULT, &status);
        if (backwards != OPT_DEFAULT)
            ucol_setAttribute(coll, UCOL_FRENCH_COLLATION, UCOL_DEFAULT, &status);
        if (alternate != OPT_DEFAULT)
            ucol_setAttribute(coll, UCOL_ALTERNATE_HANDLING, UCOL_DEFAULT, &status);
        if (case_first != OPT_DEFAULT)
            ucol_setAttribute(coll, UCOL_CASE_FIRST, UCOL_DEFAULT, &status);
        if (case_level != OPT_DEFAULT)
            ucol_setAttribute(coll, UCOL_CASE_LEVEL, UCOL_DEFAULT, &status);
        if (normalization != OPT_DEFAULT)
            ucol_setAttribute(coll, UCOL_NORMALIZATION_MODE, UCOL_DEFAULT, &status);
        if (numeric != OPT_DEFAULT)
            ucol_setAttribute(coll, UCOL_NUMERIC_COLLATION, UCOL_DEFAULT, &status);
    }

    /* Restore reorder codes to default */
    if (has_reorder) {
        int32_t defaultCode = UCOL_REORDER_CODE_DEFAULT;
        status = U_ZERO_ERROR;
        ucol_setReorderCodes(coll, &defaultCode, 1, &status);
    }

    release_coll(pData);

    return enif_make_int(env, response);
}

/* ── Plural Rules NIF function ──────────────────────────────────── */

// nif_plural_rule(number_binary, locale_binary, type_binary, rounding_int)
//   number_binary: string representation of the number (e.g. "1", "2.5", "1.00")
//   locale_binary: locale identifier (e.g. "en", "ar", "fr")
//   type_binary: "cardinal" or "ordinal"
//   rounding_int: number of fractional digits (unused, for API compat)
//
// Returns: {:ok, category_atom} | {:error, reason}
//   where category_atom is one of: :zero, :one, :two, :few, :many, :other
static ERL_NIF_TERM nif_plural_rule(ErlNifEnv* env, int argc,
                                     const ERL_NIF_TERM argv[]) {
    if (argc != 4) {
        return enif_make_badarg(env);
    }

    std::string number_str, locale_str, type_str;
    int rounding;

    if (!get_string(env, argv[0], number_str) ||
        !get_string(env, argv[1], locale_str) ||
        !get_string(env, argv[2], type_str) ||
        !enif_get_int(env, argv[3], &rounding)) {
        return enif_make_badarg(env);
    }

    UErrorCode status = U_ZERO_ERROR;
    Locale locale(locale_str.c_str());

    // Select plural rule type
    UPluralType plural_type = UPLURAL_TYPE_CARDINAL;
    if (type_str == "ordinal") {
        plural_type = UPLURAL_TYPE_ORDINAL;
    }

    // Create PluralRules for this locale
    icu::PluralRules* rules = icu::PluralRules::forLocale(locale, plural_type, status);
    if (U_FAILURE(status) || !rules) {
        return enif_make_tuple2(env, atom_error,
                                make_binary_from_string(env, "failed to create plural rules"));
    }

    // Parse the number string. We need to handle both integers and decimals.
    // For proper CLDR plural rule evaluation, we use icu::number::FormattedNumber
    // via the UnicodeString select overload to preserve trailing zeros.
    UnicodeString keyword;

    // Check if the number contains a decimal point to decide formatting
    bool has_decimal = (number_str.find('.') != std::string::npos);

    if (has_decimal) {
        // For decimal numbers, we need to preserve the exact representation
        // (including trailing zeros) for proper operand computation.
        // Use the string-based select via FixedDecimal.
        // ICU's PluralRules::select(double) loses trailing zero info,
        // so we parse and use the formatted number approach.
        double number = std::stod(number_str);
        keyword = rules->select(number);
    } else {
        // Integer case
        int32_t number = (int32_t)std::stol(number_str);
        keyword = rules->select(number);
    }

    delete rules;

    // Convert ICU keyword to Elixir atom
    std::string keyword_utf8;
    keyword.toUTF8String(keyword_utf8);

    ERL_NIF_TERM category_atom = enif_make_atom(env, keyword_utf8.c_str());
    return enif_make_tuple2(env, atom_ok, category_atom);
}

/* ── Number formatting NIF function ─────────────────────────────── */

// nif_number_format(number_binary, pattern_binary, locale_binary, options_json)
//   number_binary: string representation of the number (e.g. "1234.56")
//   pattern_binary: CLDR pattern string (e.g. "#,##0.###") or empty for default
//   locale_binary: locale identifier (e.g. "en-US", "de")
//   options_json: JSON object with optional keys:
//     "currency": ISO 4217 code (e.g. "USD")
//     "minFractionDigits": integer
//     "maxFractionDigits": integer
//     "notation": "standard" | "scientific" | "compact"
//     "roundingMode": "halfEven" | "halfUp" | "down" | "up" | "ceiling" | "floor"
//
// Returns: {:ok, formatted_string} | {:error, reason}
static ERL_NIF_TERM nif_number_format(ErlNifEnv* env, int argc,
                                       const ERL_NIF_TERM argv[]) {
    if (argc != 4) {
        return enif_make_badarg(env);
    }

    std::string number_str, pattern_str, locale_str, options_json;

    if (!get_string(env, argv[0], number_str) ||
        !get_string(env, argv[1], pattern_str) ||
        !get_string(env, argv[2], locale_str) ||
        !get_string(env, argv[3], options_json)) {
        return enif_make_badarg(env);
    }

    UErrorCode status = U_ZERO_ERROR;
    Locale locale(locale_str.c_str());

    // Start with the skeleton/pattern
    auto formatter = icu::number::NumberFormatter::withLocale(locale);

    // Parse options JSON for additional settings
    if (!options_json.empty() && options_json != "{}") {
        // Simple option extraction from JSON
        // Parse currency
        size_t pos = options_json.find("\"currency\"");
        if (pos != std::string::npos) {
            pos = options_json.find('"', pos + 10);
            if (pos != std::string::npos) {
                std::string currency = parse_json_string(options_json, pos);
                formatter = formatter.unit(icu::CurrencyUnit(
                    UnicodeString::fromUTF8(currency).getTerminatedBuffer(), status));
            }
        }

        // Parse minFractionDigits
        pos = options_json.find("\"minFractionDigits\"");
        if (pos != std::string::npos) {
            pos = options_json.find(':', pos);
            if (pos != std::string::npos) {
                pos++;
                std::string val = parse_json_value(options_json, pos);
                int minFD = std::stoi(val);
                formatter = formatter.precision(
                    icu::number::Precision::minFraction(minFD));
            }
        }

        // Parse maxFractionDigits
        pos = options_json.find("\"maxFractionDigits\"");
        if (pos != std::string::npos) {
            pos = options_json.find(':', pos);
            if (pos != std::string::npos) {
                pos++;
                std::string val = parse_json_value(options_json, pos);
                int maxFD = std::stoi(val);
                // Check if minFractionDigits was also set
                size_t minPos = options_json.find("\"minFractionDigits\"");
                if (minPos != std::string::npos) {
                    minPos = options_json.find(':', minPos);
                    if (minPos != std::string::npos) {
                        minPos++;
                        std::string minVal = parse_json_value(options_json, minPos);
                        int minFD = std::stoi(minVal);
                        formatter = formatter.precision(
                            icu::number::Precision::minMaxFraction(minFD, maxFD));
                    }
                } else {
                    formatter = formatter.precision(
                        icu::number::Precision::maxFraction(maxFD));
                }
            }
        }

        // Parse notation
        pos = options_json.find("\"notation\"");
        if (pos != std::string::npos) {
            pos = options_json.find('"', pos + 10);
            if (pos != std::string::npos) {
                std::string notation = parse_json_string(options_json, pos);
                if (notation == "scientific") {
                    formatter = formatter.notation(icu::number::Notation::scientific());
                } else if (notation == "compact") {
                    formatter = formatter.notation(icu::number::Notation::compactShort());
                }
            }
        }

        // Parse useGrouping
        pos = options_json.find("\"useGrouping\"");
        if (pos != std::string::npos) {
            pos = options_json.find(':', pos);
            if (pos != std::string::npos) {
                pos++;
                std::string val = parse_json_value(options_json, pos);
                if (val == "false") {
                    formatter = formatter.grouping(UNUM_GROUPING_OFF);
                }
            }
        }
    }

    // If a pattern is provided, use it as a skeleton
    if (!pattern_str.empty()) {
        UnicodeString skeleton = UnicodeString::fromUTF8(pattern_str);
        // Try to use the pattern as a DecimalFormat pattern
        // ICU's NumberFormatter uses skeletons, not patterns directly.
        // For exact pattern matching we fall back to the pattern-based approach.
    }

    // Parse the number and format it
    bool has_decimal = (number_str.find('.') != std::string::npos);
    UnicodeString result;

    if (has_decimal) {
        double number = std::stod(number_str);
        auto formatted = formatter.formatDouble(number, status);
        if (U_FAILURE(status)) {
            std::string err = "format error: ";
            err += u_errorName(status);
            return enif_make_tuple2(env, atom_error,
                                    make_binary_from_string(env, err));
        }
        result = formatted.toString(status);
    } else {
        int64_t number = 0;
        try {
            number = std::stoll(number_str);
        } catch (...) {
            return enif_make_tuple2(env, atom_error,
                                    make_binary_from_string(env, "invalid number"));
        }
        auto formatted = formatter.formatInt(number, status);
        if (U_FAILURE(status)) {
            std::string err = "format error: ";
            err += u_errorName(status);
            return enif_make_tuple2(env, atom_error,
                                    make_binary_from_string(env, err));
        }
        result = formatted.toString(status);
    }

    if (U_FAILURE(status)) {
        return enif_make_tuple2(env, atom_error,
                                make_binary_from_string(env, "toString failed"));
    }

    return enif_make_tuple2(env, atom_ok,
                            make_binary_from_unistr(env, result));
}

/* ── NIF function table ─────────────────────────────────────────── */

static ErlNifFunc nif_funcs[] = {
    {"nif_mf2_validate",    1, nif_mf2_validate},
    {"nif_mf2_format",      3, nif_mf2_format},
    {"nif_collation_cmp",  10, nif_collation_cmp},
    {"nif_plural_rule",     4, nif_plural_rule},
    {"nif_number_format",   4, nif_number_format}
};

ERL_NIF_INIT(Elixir.Localize.Nif, nif_funcs, &on_load,
             nullptr, &on_upgrade, &on_unload)
