### 目录结构

学习wpa_supplicant的makefile
```
.
├── build
│   └── wpa_supplicant
│       ├── dbus
│       └── src
│           ├── ap
│           ├── common
│           ├── crypto
│           ├── drivers
│           ├── eap_common
│           ├── eap_peer
│           ├── eap_server
│           ├── eapol_auth
│           ├── eapol_supp
│           ├── l2_packet
│           ├── p2p
│           ├── pae
│           ├── radius
│           ├── rsn_supp
│           ├── tls
│           ├── utils
│           └── wps
├── hs20
│   └── client
├── src
│   ├── ap
│   ├── common
│   ├── crypto
│   ├── drivers
│   ├── eap_common
│   ├── eap_peer
│   ├── eap_server
│   ├── eapol_auth
│   ├── eapol_supp
│   ├── fst
│   ├── l2_packet
│   ├── p2p
│   ├── pae
│   ├── radius
│   ├── rsn_supp
│   ├── tls
│   ├── utils
│   └── wps
└── wpa_supplicant
    ├── binder
    │   └── fi
    │       └── w1
    │           └── wpa_supplicant
    ├── dbus
    ├── doc
    │   └── docbook
    ├── examples
    │   └── p2p
    ├── systemd
    ├── utils
    ├── vs2005
    │   ├── eapol_test
    │   ├── win_if_list
    │   ├── wpa_cli
    │   ├── wpa_passphrase
    │   ├── wpa_supplicant
    │   └── wpasvc
    └── wpa_gui-qt4
        ├── icons
        └── lang
```

### 分析

* 在wpa_supplicat/Makefile中设置需要编译文件已经产物名称

* wpa_supplicant目录的Makefile调用src/build.rules目录编译目标文件

* build.rules中设置了.c生成.o的规则

* objs.mk用于更新目标文件名称，已经获取目标文件目录

* lib.rules

* make所有产物放在build目录，并根据代码中的位置，创建对应的子目录

### build.rules

```
.PHONY: all
all: _all

# disable built-in rules
.SUFFIXES:

# setup some variables
# make程序在读取多个makefile文件时，包括由环境变量"MAKEFILES"指定、
# 命令行指定、当前工作下的默认的以及使用指示符“include”指定包含的，
# 在这些文件进行解析执行之前make读取的文件名将会被自动依次追加到变量"MAKEFILE_LIST"的定义域中。
# 这样我们就可以通过测试此变量的最后一个字来获取当前make程序正在处理的makefile文件名。
# 具体的说就是在一个makefile文件中如果使用指示符"include"包含另一个文件之后，
# 变量"MAKEFILE_LIST"的最后一个字只可能是指示符"include"指定所要包含的那个文件的名字。
# lastword提取变量最后一个元素
# dir获取路径名称
ROOTDIR := $(dir $(lastword $(MAKEFILE_LIST)))
# $(ROOTDIR:%../src/=%)与patsubst函数用法一样，将ROOTDIR中，满足%../src/都替换成%
ROOTDIR := $(dir $(ROOTDIR:%../src/=%))../
# 获取绝对路径，编译目录
BUILDDIR ?= $(abspath $(ROOTDIR)build)
# 给路径末尾添加'/'
BUILDDIR := $(BUILDDIR:%/=%)
ABSROOT := $(abspath $(ROOTDIR))
ifeq ($(origin OUT),command line)
_PROJ := $(OUT:%/=%)
_PROJ := $(_PROJ:$(BUILDDIR)/%=%)
else
_PROJ := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
_PROJ := $(_PROJ:$(ABSROOT)/%=%)
$(warning $(_PROJ))
endif

ifndef CC
CC=gcc
endif

ifndef RANLIB
RANLIB=ranlib
endif

ifndef LDO
LDO=$(CC)
endif

ifndef CFLAGS
# -MM选项，-MM生成文件以来关系，但是不包含标准库头文件
# -D选项，生成的以来关系输出到以.d为后缀的文件。文件名称由-O指定
CFLAGS = -MMD -O2 -Wall -g
endif
# 添加config文件
ifneq ($(CONFIG_FILE),)
-include $(CONFIG_FILE)

# export for sub-makefiles
export CONFIG_CODE_COVERAGE
# .config检查
.PHONY: verify_config
verify_config:
	@if [ ! -r $(CONFIG_FILE) ]; then \
		echo 'Building $(firstword $(ALL)) requires a configuration file'; \
		echo '(.config). See README for more instructions. You can'; \
		echo 'run "cp defconfig .config" to create an example'; \
		echo 'configuration.'; \
		exit 1; \
	fi
VERIFY := verify_config
else
VERIFY :=
endif

# default target
.PHONY: _all
_all: $(VERIFY) $(ALL) $(EXTRA_TARGETS)

# continue setup
COVSUFFIX := $(if $(CONFIG_CODE_COVERAGE),-cov,)
PROJ := $(_PROJ)$(COVSUFFIX)

Q=@
E=echo
ifeq ($(V), 1)
Q=
E=true
endif
ifeq ($(QUIET), 1)
Q=@
E=true
endif

ifeq ($(Q),@)
MAKEFLAGS += --no-print-directory
endif

_DIRS := $(BUILDDIR)/$(PROJ)
.PHONY: _make_dirs
_make_dirs:
	$(warning $(_DIRS))
	@mkdir -p $(_DIRS)
# 此处就是真正的生成语法了，表示了.o文件如何通过.c文件生成
# 在目录中找.c文件，编译的.o文件产物都放到build目录对应的子目录中
# src目录的.o规则
$(BUILDDIR)/$(PROJ)/src/%.o: $(ROOTDIR)src/%.c $(CONFIG_FILE) | _make_dirs
	$(Q)$(CC) -c -o $@ $(CFLAGS) $<
	@$(E) "  CC " $<

# $(PROJ)/.o生成规则，
$(BUILDDIR)/$(PROJ)/%.o: %.c $(CONFIG_FILE) | _make_dirs
	$(Q)$(CC) -c -o $@ $(CFLAGS) $<
	@$(E) "  CC " $<
# for the fuzzing tests
$(BUILDDIR)/$(PROJ)/wpa_supplicant/%.o: $(ROOTDIR)wpa_supplicant/%.c $(CONFIG_FILE) | _make_dirs
	$(Q)$(CC) -c -o $@ $(CFLAGS) $<
	@$(E) "  CC " $<

# libraries - they know how to build themselves
# (lib_phony so we recurse all the time)
.PHONY: lib_phony
lib_phony:
# nothing
# .a生成规则,进入不同的子目录，编译.a库
$(BUILDDIR)/$(PROJ)/%.a: $(CONFIG_FILE) lib_phony
	$(Q)$(MAKE) -C $(ROOTDIR)$(dir $(@:$(BUILDDIR)/$(PROJ)/%=%)) OUT=$(abspath $(dir $@))/
# 编译函数
# $(1)的参数进行替换，在ROOTDIR目录下的，都去掉路径, $(1)就是需要编译的一堆.o文件
# 将所有的文件都放到$(BUILDDIR)/$(PROJ)目录
BUILDOBJ = $(patsubst %,$(BUILDDIR)/$(PROJ)/%,$(patsubst $(ROOTDIR)%,%,$(1)))

.PHONY: common-clean
common-clean:
	$(Q)rm -rf $(ALL) $(BUILDDIR)/$(PROJ)

```

### objs.mk

```
# 调用编译函数，传入的参数_OBJS_VAR
# 每次调用之前，都对_OBJS_VAR变量重新赋值
#
$(_OBJS_VAR) := $(call BUILDOBJ,$($(_OBJS_VAR)))
# '-'表示出错或执行失败时，不报错，继续运行，不停止
# $(_OBJS_VAR):%.o=%.d将所有的.o文件替换成.d文件
# filter-out,去掉.a文件
-include $(filter-out %.a,$($(_OBJS_VAR):%.o=%.d))
# 获取所有文件的目录
_DIRS += $(dir $($(_OBJS_VAR)))
```

### lib.rules
```
_LIBMK := $(lastword $(wordlist 1,$(shell expr $(words $(MAKEFILE_LIST)) - 1),$(MAKEFILE_LIST)))
_LIBNAME := $(notdir $(patsubst %/,%,$(dir $(abspath $(_LIBMK)))))
ALL := $(OUT)lib$(_LIBNAME).a
# 获取当前Makefile的路径
LIB_RULES := $(lastword $(MAKEFILE_LIST))
# 
include $(dir $(LIB_RULES))build.rules

ifdef TEST_FUZZ
CFLAGS += -DCONFIG_NO_RANDOM_POOL
CFLAGS += -DTEST_FUZZ
endif

CFLAGS += $(FUZZ_CFLAGS)
CFLAGS += -I.. -I../utils

_OBJS_VAR := LIB_OBJS
include ../objs.mk

$(ALL): $(LIB_OBJS)
	@$(E) "  AR  $(notdir $@)"
	$(Q)$(AR) crT $@ $?

install-default:
	@echo Nothing to be made.

%: %-default
	@true

clean: common-clean
	$(Q)rm -f *~ *.o *.d $(ALL)
```
