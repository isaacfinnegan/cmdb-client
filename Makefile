NAME=cmdb-client
VERSION=1.0
RELEASE=1
SOURCE=$(NAME)-$(VERSION).tar.gz
EXES=cmdbclient
LIBS=
CONFS=
ARCH=noarch
CLEAN_TARGETS=$(SPEC) $(NAME)-$(VERSION) $(SOURCE) # for in-house package

include $(shell starter)/rules.mk
