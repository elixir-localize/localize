ERL ?= erl
BASEDIR=$(CURDIR)
PRIVDIR=./priv

NIF_DIR=c_src
NIF_ENV=c_src/env.mk

NIF_SOURCES=$(NIF_DIR)/localize_nif.c
NIF_OBJS=$(NIF_DIR)/localize_nif.o
NIF_SO=$(PRIVDIR)/localize_nif.so

UNAME_SYS := $(shell uname -s)
UNAME_ARCH := $(shell uname -p)

ifeq ($(UNAME_SYS), Darwin)
	ifeq ($(UNAME_ARCH), arm)
		CC ?= cc
		CFLAGS = -O3 -std=c99 -arch arm64 -Wall -Wmissing-prototypes -DDARWIN
		LDFLAGS = -arch arm64 -flat_namespace -undefined dynamic_lookup
	else
		CC ?= cc
		CFLAGS = -O3 -std=c99 -arch x86_64 -Wall -Wmissing-prototypes -DDARWIN
		LDFLAGS = -arch x86_64 -flat_namespace -undefined dynamic_lookup
	endif
else ifeq ($(UNAME_SYS), FreeBSD)
	CC ?= cc
	CFLAGS ?= -O3 -std=c99 -finline-functions -Wall -Wmissing-prototypes
else ifeq ($(UNAME_SYS), Linux)
	CC ?= gcc
	CFLAGS ?= -O3 -std=c99 -finline-functions -Wall -Wmissing-prototypes
endif

CFLAGS += -fPIC -I$(ERTS_INCLUDE_DIR) -I$(ERL_INTERFACE_INCLUDE_DIR)

# On OTP 23 and later, liberl_interface.a doesn't exist and
# isn't required

ifneq ("$(wildcard $(ERL_INTERFACE_LIB_DIR)/liberl_interface.a)","")
    LDLIBS += -L$(ERL_INTERFACE_LIB_DIR) -lerl_interface -lei
else
    LDLIBS += -L$(ERL_INTERFACE_LIB_DIR) -lei
endif

LDFLAGS += -shared

ICU_CFLAGS = $(shell pkg-config --cflags icu-uc icu-io --silence-errors)
ICU_LIBS = $(shell pkg-config --libs icu-uc icu-io --silence-errors)

ifeq ($(ICU_LIBS),)
  ifeq ($(UNAME_SYS), Darwin)
		ICU_CFLAGS = -I$(BASEDIR)/c_src/platform/osx/icu
		ICU_LIBS = -lpthread -lm -licucore -lstdc++
	endif
endif

ifeq ($(ICU_LIBS),)
  $(error ICU_LIBS not set, is pkg-config installed?)
endif

all: $(NIF_ENV) $(NIF_SO)

clean:
	@rm -rf $(NIF_SO) $(NIF_OBJS)

distclean: clean
	@rm -rf $(NIF_ENV)

$(NIF_SO): $(NIF_OBJS)
	@mkdir -p $(PRIVDIR)
	$(CC) $(NIF_OBJS) $(LDFLAGS) $(LDLIBS) $(ICU_LIBS) -o $(NIF_SO)

%.o: %.c
	@$(CC) -c $(CFLAGS) $(CPPFLAGS) $(ICU_CFLAGS) $< -o $@

$(NIF_ENV):
	@$(ERL) -eval "file:write_file(\"$(NIF_ENV)\", \
		io_lib:format( \
		\"ERTS_INCLUDE_DIR ?= ~s/erts-~s/include/~n\" \
		\"ERL_INTERFACE_INCLUDE_DIR ?= ~s~n\" \
		\"ERL_INTERFACE_LIB_DIR ?= ~s~n\", \
		[code:root_dir(), erlang:system_info(version), \
		code:lib_dir(erl_interface, include), \
		code:lib_dir(erl_interface, lib)])), \
		halt()."

-include $(NIF_ENV)
