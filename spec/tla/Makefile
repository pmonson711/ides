TLA2TOOLS_JAR ?= /home/pmonson/.local/opt/tla-toolbox/1.8.0/toolbox/tla2tools.jar
DTLA_LIB      ?= /home/pmonson/.local/opt/tla-toolbox/CommunityModules/modules

TLA_CP       := $(TLA2TOOLS_JAR):$(DTLA_LIB)
TLA_FLAGS    := -XX:+UseParallelGC

MODELS := \
	MCOneForOne \
	MCOneForAll \
	MCRestForOne \
	MCSimpleOneForOne \
	MCNestedEscalation \
	MCLinkKill \
	MCMonitorCrash \
	MCNestedDeep3 \
	MCNestedDeep4 \
	MCStartup

.PHONY: all check $(MODELS) clean

all: check

check: $(MODELS)

$(MODELS):
	@echo "=== $@ ==="
	java $(TLA_FLAGS) -cp $(TLA_CP) tlc2.TLC -config $@.cfg $@.tla
	@echo

clean:
	rm -rf *_TTrace_*.tla *_TTrace_*.bin states
