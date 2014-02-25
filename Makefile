NAME=cmdb-client
VERSION=1.1.1
RELEASE=1
SOURCE=$(NAME)-$(VERSION).tar.gz
EXES=cmdbclient
LIBS=CMDB
CONFS=
ARCH=noarch
CLEAN_TARGETS=$(SPEC) $(NAME)-$(VERSION) $(SOURCE) # for in-house package

include $(shell starter)/rules.mk




$(NAME)-$(VERSION): $(FILES) $(EXES) $(CONFS) $(LIBS)
	mkdir -p $(NAME)-$(VERSION)
	if [ -n "$(FILES)" ]; then tar cf - $(FILES) | (cd $(NAME)-$(VERSION) && tar xf -); $(BUILD_HOME)/rmsvn $(NAME)-$(VERSION); fi
	if [ -n "$(EXES)" ]; then $(ENSURE_DIR) $(NAME)-$(VERSION)/bin && $(MAKE_EXES) $(EXES) $(NAME)-$(VERSION)/bin; fi
	if [ -n "$(CONFS)" ]; then $(ENSURE_DIR) $(NAME)-$(VERSION)/etc && $(MAKE_CONFS) $(CONFS) $(NAME)-$(VERSION)/etc; fi
	if [ -n "$(LIBS)" ]; then $(ENSURE_DIR) $(NAME)-$(VERSION)/lib/perl/$(PERL_VERSION) && $(MAKE_LIBS) $(LIBS) $(NAME)-$(VERSION)/lib; tar cf - $(LIBS) | (cd $(NAME)-$(VERSION)/lib/perl/$(PERL_VERSION) && tar xf -);fi
#TODO fix this special case for ruby lib
	$(ENSURE_DIR) $(NAME)-$(VERSION)/lib/site_ruby/$(RUBY_VERSION) && $(MAKE_LIBS) $(LIBS) $(NAME)-$(VERSION)/lib; cp cmdbclient.rb $(NAME)-$(VERSION)/lib/site_ruby/$(RUBY_VERSION)
	if [ -n "$(EXES)$(LIBS)" ]; then $(ENSURE_DIR) $(NAME)-$(VERSION)/man && $(MAKE_MANS) --release="$(NAME) $(VERSION)" $(EXES) $(LIBS) $(NAME)-$(VERSION)/man; fi
