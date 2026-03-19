/*
 * NIF infrastructure for the localize library.
 *
 * This file provides the NIF lifecycle hooks and function table.
 * No NIF functions are exported yet — the build system and Elixir
 * wrapper are ready for future ICU4C functions (unit formatting,
 * measurement systems, number formatting, etc.).
 */

#ifdef DARWIN
#define U_HIDE_DRAFT_API 1
#define U_DISABLE_RENAMING 1
#endif

#include "erl_nif.h"
#include <stdio.h>

/* ------------------------------------------------------------------ */

static int
on_load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM info)
{
    *priv_data = NULL;
    return 0;
}

static void
on_unload(ErlNifEnv* env, void* priv_data)
{
}

static int
on_reload(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM info)
{
    return 0;
}

static int
on_upgrade(ErlNifEnv* env, void** priv_data, void** old_data, ERL_NIF_TERM info)
{
    *priv_data = NULL;
    return 0;
}

/* ------------------------------------------------------------------ */

static ErlNifFunc
nif_funcs[] =
{
    /* Future NIF functions will be added here */
};

ERL_NIF_INIT(Elixir.Localize.Nif, nif_funcs, &on_load, &on_reload, &on_upgrade, &on_unload)
