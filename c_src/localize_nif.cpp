// Localize NIF: ICU4C bindings for the localize library.
//
// Currently provides MessageFormat 2.0 functions:
//   nif_mf2_validate/1 - Parse a message and return normalized pattern or error
//   nif_mf2_format/3   - Format a message with locale and JSON-encoded arguments
//
// Future functions for number, date/time, unit formatting etc. will be
// added to the nif_funcs table below.

#include <cstring>
#include <map>
#include <string>

#ifdef DARWIN
#define U_HIDE_DRAFT_API 1
#define U_DISABLE_RENAMING 1
#endif

#include "erl_nif.h"

#include "unicode/errorcode.h"
#include "unicode/locid.h"
#include "unicode/messageformat2.h"
#include "unicode/messageformat2_arguments.h"
#include "unicode/messageformat2_formattable.h"
#include "unicode/parseerr.h"
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

/* ── Lifecycle ──────────────────────────────────────────────────── */

static int
on_load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM info)
{
    atom_ok = enif_make_atom(env, "ok");
    atom_error = enif_make_atom(env, "error");
    *priv_data = NULL;
    return 0;
}

static void
on_unload(ErlNifEnv* env, void* priv_data)
{
}

static int
on_upgrade(ErlNifEnv* env, void** priv_data, void** old_data, ERL_NIF_TERM info)
{
    atom_ok = enif_make_atom(env, "ok");
    atom_error = enif_make_atom(env, "error");
    *priv_data = NULL;
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

/* ── NIF function table ─────────────────────────────────────────── */

static ErlNifFunc nif_funcs[] = {
    {"nif_mf2_validate", 1, nif_mf2_validate},
    {"nif_mf2_format",   3, nif_mf2_format}
};

ERL_NIF_INIT(Elixir.Localize.Nif, nif_funcs, &on_load,
             nullptr, &on_upgrade, &on_unload)
