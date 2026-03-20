ERL ?= erl
BASEDIR=$(CURDIR)
PRIVDIR=./priv

NIF_DIR=c_src
NIF_ENV=c_src/env.mk

NIF_SOURCES=$(NIF_DIR)/localize_nif.cpp
NIF_OBJS=$(NIF_DIR)/localize_nif.o
NIF_SO=$(PRIVDIR)/localize_nif.so

UNAME_SYS := $(shell uname -s)
UNAME_ARCH := $(shell uname -p)

ifeq ($(UNAME_SYS), Darwin)
	ifeq ($(UNAME_ARCH), arm)
		CXX ?= c++
		CXXFLAGS = -O3 -std=c++17 -arch arm64 -Wall
		LDFLAGS = -arch arm64 -flat_namespace -undefined dynamic_lookup
	else
		CXX ?= c++
		CXXFLAGS = -O3 -std=c++17 -arch x86_64 -Wall
		LDFLAGS = -arch x86_64 -flat_namespace -undefined dynamic_lookup
	endif
else ifeq ($(UNAME_SYS), FreeBSD)
	CXX ?= c++
	CXXFLAGS ?= -O3 -std=c++17 -finline-functions -Wall
else ifeq ($(UNAME_SYS), Linux)
	CXX ?= g++
	CXXFLAGS ?= -O3 -std=c++17 -finline-functions -Wall
endif

CXXFLAGS += -fPIC -I$(ERTS_INCLUDE_DIR) -I$(ERL_INTERFACE_INCLUDE_DIR)

# On OTP 23 and later, liberl_interface.a doesn't exist and
# isn't required
ifneq ("$(wildcard $(ERL_INTERFACE_LIB_DIR)/liberl_interface.a)","")
    LDLIBS += -L$(ERL_INTERFACE_LIB_DIR) -lerl_interface -lei
else
    LDLIBS += -L$(ERL_INTERFACE_LIB_DIR) -lei
endif

LDFLAGS += -shared

# ICU detection: MF2 requires icu-uc and icu-i18n
# On macOS with Homebrew, we need to set PKG_CONFIG_PATH since icu4c is keg-only
ifeq ($(UNAME_SYS), Darwin)
  HOMEBREW_ICU_DIR := $(shell [ -d /usr/local/opt/icu4c/lib/pkgconfig ] && echo /usr/local/opt/icu4c/lib/pkgconfig || ([ -d /opt/homebrew/opt/icu4c/lib/pkgconfig ] && echo /opt/homebrew/opt/icu4c/lib/pkgconfig || echo ""))
  ifneq ($(HOMEBREW_ICU_DIR),)
    export PKG_CONFIG_PATH := $(HOMEBREW_ICU_DIR):$(PKG_CONFIG_PATH)
  endif
endif

ICU_CFLAGS = $(shell pkg-config --cflags icu-uc icu-i18n 2>/dev/null)
ICU_LIBS = $(shell pkg-config --libs icu-uc icu-i18n 2>/dev/null)

ifeq ($(ICU_LIBS),)
  ifeq ($(UNAME_SYS), Darwin)
    # Fallback: try to find Homebrew ICU directly
    HOMEBREW_ICU := $(shell [ -d /usr/local/opt/icu4c ] && echo /usr/local/opt/icu4c || ([ -d /opt/homebrew/opt/icu4c ] && echo /opt/homebrew/opt/icu4c || echo ""))
    ifneq ($(HOMEBREW_ICU),)
      ICU_CFLAGS = -I$(HOMEBREW_ICU)/include
      ICU_LIBS = -L$(HOMEBREW_ICU)/lib -licuuc -licui18n -licudata -lstdc++
    endif
  endif
endif

ifeq ($(ICU_LIBS),)
  $(error ICU libraries not found. Install ICU 75+ with MF2 support. On macOS: brew install icu4c)
endif

all: $(NIF_ENV) $(NIF_SO)

clean:
	@rm -rf $(NIF_SO) $(NIF_OBJS)

distclean: clean
	@rm -rf $(NIF_ENV)

$(NIF_SO): $(NIF_OBJS)
	@mkdir -p $(PRIVDIR)
	$(CXX) $(NIF_OBJS) $(LDFLAGS) $(LDLIBS) $(ICU_LIBS) -o $(NIF_SO)

%.o: %.cpp
	$(CXX) -c $(CXXFLAGS) $(ICU_CFLAGS) $< -o $@

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
