BASE_DIR         = $(shell pwd)
ERLANG_BIN       = $(shell dirname $(shell which erl))
GIT_VERSION      = $(shell git describe --tags --always)
OVERLAY_VARS    ?=
REBAR ?= $(BASE_DIR)/rebar3

$(if $(ERLANG_BIN),,$(warning "Warning: No Erlang found in your path, this will probably not work"))


all: compile

compile:
	$(REBAR) $(PROFILE) compile


##
## Release targets
##
rel:
	cat vars.config > vars.generated
	echo "{app_version, \"${GIT_VERSION}\"}." >> vars.generated
ifeq ($(OVERLAY_VARS),)
else
	echo "%% including OVERLAY_VARS from an additional file." >> vars.generated
	echo \"./${OVERLAY_VARS}\". >> vars.generated
endif
	$(REBAR) $(PROFILE) release

##
## Developer targets
##

## build a release including debugger and wx
## after a fresh checkout, run 'make rel' (to create default release),
## then 'make debug_build'
debug_build: PROFILE = as debug_build
debug_build: rel

##  devN - Make a dev build for node N
dev% :
	./gen_dev $@ vars/dev_vars.config.src vars/$@_vars.config
	cat vars/$@_vars.config > vars.generated
	(./rebar3 as $@ release)

.PHONY: all compile rel
export OVERLAY_VARS
