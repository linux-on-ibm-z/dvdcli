# configure make
export MAKEFLAGS := $(MAKEFLAGS) --no-print-directory -k

# store the current working directory
CWD := $(shell pwd)

# enable go 1.5 vendoring
export GO15VENDOREXPERIMENT := 1

# set the go os and architecture types as well the sed command to use based on
# the os and architecture types
ifeq ($(OS),Windows_NT)
	GOOS ?= windows
	ifeq ($(PROCESSOR_ARCHITECTURE),AMD64)
		export GOARCH ?= amd64
	endif
	ifeq ($(PROCESSOR_ARCHITECTURE),x86)
		export GOARCH ?= 386
	endif
else
	UNAME_S := $(shell uname -s)
	ifeq ($(UNAME_S),Linux)
		export GOOS ?= linux
	endif
	ifeq ($(UNAME_S),Darwin)
		export GOOS ?= darwin
		export GOARCH ?= amd64
	endif
	ifeq ($(origin GOARCH), undefined)
		UNAME_P := $(shell uname -p)
		ifeq ($(UNAME_P),x86_64)
			export GOARCH = amd64
		endif
		ifneq ($(filter %86,$(UNAME_P)),)
			export GOARCH = 386
		endif
		ifeq ($(UNAME_P),s390x)
			export GOARCH = s390x
		endif
	endif
endif

# init the build platforms
BUILD_PLATFORMS ?= Linux-i386 Linux-x86_64 Darwin-x86_64 Linux-s390x

# init the internal go os and architecture variable values used for naming files
_GOOS ?= $(GOOS)
_GOARCH ?= $(GOARCH)

# parse a semver
SEMVER_PATT := ^[^\d]*(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z].+?))?(?:-(\d+)-g(.+?)(?:-(dirty))?)?$$
PARSE_SEMVER = $(shell echo $(1) | perl -pe 's/$(SEMVER_PATT)/$(2)/gim')

# describe the git information and create a parsing function for it
GIT_DESCRIBE := $(shell git describe --long --dirty)
PARSE_GIT_DESCRIBE = $(call PARSE_SEMVER,$(GIT_DESCRIBE),$(1))

# parse the version components from the git information
V_MAJOR := $(call PARSE_GIT_DESCRIBE,$$1)
V_MINOR := $(call PARSE_GIT_DESCRIBE,$$2)
V_PATCH := $(call PARSE_GIT_DESCRIBE,$$3)
V_NOTES := $(call PARSE_GIT_DESCRIBE,$$4)
V_BUILD := $(call PARSE_GIT_DESCRIBE,$$5)
V_SHA_SHORT := $(call PARSE_GIT_DESCRIBE,$$6)
V_DIRTY := $(call PARSE_GIT_DESCRIBE,$$7)

# the version's binary os and architecture type
ifeq ($(_GOOS),windows)
	V_OS := Windows_NT
endif
ifeq ($(_GOOS),linux)
	V_OS := Linux
endif
ifeq ($(_GOOS),darwin)
	V_OS := Darwin
endif
ifeq ($(_GOARCH),386)
	V_ARCH := i386
endif
ifeq ($(_GOARCH),amd64)
	V_ARCH := x86_64
endif

ifeq ($(_GOARCH),s390x)
	V_ARCH := s390x
endif

V_OS_ARCH := $(V_OS)-$(V_ARCH)

# the long commit hash
V_SHA_LONG := $(shell git show HEAD -s --format=%H)

# the branch name, possibly from travis-ci
ifeq ($(origin TRAVIS_BRANCH), undefined)
	TRAVIS_BRANCH := $(shell git branch | grep '*' | awk '{print $$2}')
else
	ifeq ($(strip $(TRAVIS_BRANCH)),)
		TRAVIS_BRANCH := $(shell git branch | grep '*' | awk '{print $$2}')
	endif
endif
ifeq ($(origin TRAVIS_TAG), undefined)
	TRAVIS_TAG := $(TRAVIS_BRANCH)
else
	ifeq ($(strip $(TRAVIS_TAG)),)
		TRAVIS_TAG := $(TRAVIS_BRANCH)
	endif
endif
V_BRANCH := $(TRAVIS_TAG)

# the build date as an epoch
V_EPOCH := $(shell date +%s)

# the build date
V_BUILD_DATE := $(shell perl -e 'use POSIX strftime; print strftime("%a, %d %b %Y %H:%M:%S %Z", localtime($(V_EPOCH)))')

# the release date as required by bintray
V_RELEASE_DATE := $(shell perl -e 'use POSIX strftime; print strftime("%Y-%m-%d", localtime($(V_EPOCH)))')

# init the semver
V_SEMVER := $(V_MAJOR).$(V_MINOR).$(V_PATCH)
ifneq ($(V_NOTES),)
	V_SEMVER := $(V_SEMVER)-$(V_NOTES)
endif

# get the version file's version
V_FILE := $(strip $(shell cat VERSION 2> /dev/null))

# append the build number and dirty values to the semver if appropriate
ifneq ($(V_BUILD),)
	ifneq ($(V_BUILD),0)
		# if the version file's version is different than the version parsed from the
		# git describe information then use the version file's version
		ifneq ($(V_SEMVER),$(V_FILE))
			V_MAJOR := $(call PARSE_SEMVER,$(V_FILE),$$1)
			V_MINOR := $(call PARSE_SEMVER,$(V_FILE),$$2)
			V_PATCH := $(call PARSE_SEMVER,$(V_FILE),$$3)
			V_NOTES := $(call PARSE_SEMVER,$(V_FILE),$$4)
			V_SEMVER := $(V_MAJOR).$(V_MINOR).$(V_PATCH)
			ifneq ($(V_NOTES),)
				V_SEMVER := $(V_SEMVER)-$(V_NOTES)
			endif
		endif
		V_SEMVER := $(V_SEMVER)+$(V_BUILD)
	endif
endif
ifeq ($(V_DIRTY),dirty)
	V_SEMVER := $(V_SEMVER)+$(V_DIRTY)
endif

# the rpm version cannot have any dashes
V_RPM_SEMVER := $(subst -,+,$(V_SEMVER))

GOFLAGS := $(GOFLAGS)
GLIDE := $(GOPATH)/bin/glide
NV := $$($(GLIDE) novendor)
BASEPKG := github.com/emccode/dvdcli
BASEDIR := $(GOPATH)/src/$(BASEPKG)
BASEDIR_NAME := $(shell basename $(BASEDIR))
BASEDIR_PARENTDIR := $(shell dirname $(BASEDIR))
BASEDIR_TEMPMVLOC := $(BASEDIR_PARENTDIR)/.$(BASEDIR_NAME)-$(shell date +%s)
VERSIONPKG := $(BASEPKG)/version_info
LDF_SEMVER := -X $(VERSIONPKG).SemVer=$(V_SEMVER)
LDF_BRANCH := -X $(VERSIONPKG).Branch=$(V_BRANCH)
LDF_EPOCH := -X $(VERSIONPKG).Epoch=$(V_EPOCH)
LDF_SHA_LONG := -X $(VERSIONPKG).ShaLong=$(V_SHA_LONG)
LDF_ARCH = -X $(VERSIONPKG).Arch=$(V_OS_ARCH)
LDFLAGS = -ldflags "$(LDF_SEMVER) $(LDF_BRANCH) $(LDF_EPOCH) $(LDF_SHA_LONG) $(LDF_ARCH)"
RPMBUILD := $(CWD)/.rpmbuild
EMCCODE := $(GOPATH)/src/github.com/emccode
PRINT_STATUS = export EC=$$?; cd $(CWD); if [ "$$EC" -eq "0" ]; then printf "SUCCESS!\n"; else exit $$EC; fi
STAT_FILE_SIZE = stat --format '%s' $$FILE 2> /dev/null || stat -f '%z' $$FILE 2> /dev/null

all: install

_pre-make:
	@if [ "$(CWD)" != "$(BASEDIR)" ]; then \
		if [ -e "$(BASEDIR)" ]; then \
			mv $(BASEDIR) $(BASEDIR_TEMPMVLOC); \
		fi; \
		mkdir -p "$(BASEDIR_PARENTDIR)"; \
		ln -s "$(CWD)" "$(BASEDIR)"; \
	fi

_post-make:
	@if [ -e "$(BASEDIR_TEMPMVLOC)" -a -L $(BASEDIR) ]; then \
		rm -f $(BASEDIR); \
		mv $(BASEDIR_TEMPMVLOC) $(BASEDIR); \
	fi

deps: _pre-make _deps _post-make
_deps:
	@if [ -z "$$OFFLINE" ]; then \
		echo "target: deps"; \
		printf "  ...installing glide..."; \
		go get github.com/Masterminds/glide; \
			$(PRINT_STATUS); \
		printf "  ...downloading go dependencies..."; \
			cd $(BASEDIR); \
			go get -d $(GOFLAGS) $(NV); \
			$(GLIDE) -q up 2> /dev/null; \
			$(PRINT_STATUS); \
	fi

build: _pre-make _build _post-make
_build: _deps _fmt build_
build_:
	@echo "target: build"
	@printf "  ...building dvdcli $(V_OS_ARCH)..."; \
		cd $(BASEDIR); \
		FILE=.bin/$(V_OS_ARCH)/dvdcli; \
		env GOOS=$(_GOOS) GOARCH=$(_GOARCH) go build -o $$FILE $(GOFLAGS) $(LDFLAGS) ./dvdcli; \
		$(PRINT_STATUS); \
		if [ "$$EC" -eq "0" ]; then \
			mkdir -p .deploy/$(V_OS_ARCH); \
			mkdir -p .deploy/latest; \
			cd .bin/$(V_OS_ARCH); \
			TARBALL=dvdcli-$(V_OS_ARCH)-$(V_SEMVER).tar.gz; \
			LATEST=dvdcli-$(V_OS_ARCH).tar.gz; \
			tar -czf $$TARBALL dvdcli; \
			cp -f $$TARBALL ../../.deploy/latest/$$LATEST; \
			mv -f $$TARBALL ../../.deploy/$(V_OS_ARCH); \
			cd - > /dev/null ; \
			BYTES=$$($(STAT_FILE_SIZE)); \
			SIZE=$$(($$BYTES / 1024 / 1024)); \
			printf "\nThe dvdcli binary is $${SIZE}MB and located at:\n\n"; \
			printf "  $$FILE\n\n"; \
		fi

build-all: _pre-make version-noarch _deps _fmt build-all_ _post-make
build-all_: build-linux-386_ build-linux-amd64_ build-darwin-amd64_ build-linux-s390x_

deploy-prep:
	@echo "target: deploy-prep"
	@printf "  ...preparing deployment..."; \
		sed -e 's/$${SEMVER}/$(V_SEMVER)/g' \
			-e 's|$${DSCRIP}|$(V_SEMVER).Branch.$(V_BRANCH).Sha.$(V_SHA_LONG)|g' \
			-e 's/$${RELDTE}/$(V_RELEASE_DATE)/g' \
			.bintray-stupid.json > .bintray-stupid-filtered.json; \
		sed -e 's/$${SEMVER}/$(V_SEMVER)/g' \
			-e 's|$${DSCRIP}|$(V_SEMVER).Branch.$(V_BRANCH).Sha.$(V_SHA_LONG)|g' \
			-e 's/$${RELDTE}/$(V_RELEASE_DATE)/g' \
			.bintray-staged.json > .bintray-staged-filtered.json; \
		sed -e 's/$${SEMVER}/$(V_SEMVER)/g' \
			-e 's|$${DSCRIP}|$(V_SEMVER).Branch.$(V_BRANCH).Sha.$(V_SHA_LONG)|g' \
			-e 's/$${RELDTE}/$(V_RELEASE_DATE)/g' \
			.bintray-stable.json > .bintray-stable-filtered.json;\
		printf "SUCCESS!\n"

build-linux-386: _pre-make _build-linux-386 _post-make
_build-linux-386: _deps _fmt build-linux-386_
build-linux-386_:
	@if [ "" != "$(findstring Linux-i386,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=linux _GOARCH=386 make build_; \
	fi
rebuild-linux-386: _pre-make _clean _build-linux-386 _post-make
rebuild-all-linux-386: _pre-make _clean-all _build-linux-386 _post-make

build-linux-amd64: _pre-make _build-linux-amd64 _post-make
_build-linux-amd64: _deps _fmt build-linux-amd64_
build-linux-amd64_:
	@if [ "" != "$(findstring Linux-x86_64,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=linux _GOARCH=amd64 make build_; \
	fi
rebuild-linux-amd64: _pre-make _clean _build-linux-amd64 _post-make
rebuild-all-linux-amd64: _pre-make _clean-all _build-linux-amd64 _post-make


build-darwin-amd64: _pre-make _build-darwin-amd64 _post-make
_build-darwin-amd64: _deps _fmt build-darwin-amd64_
build-darwin-amd64_:
	@if [ "" != "$(findstring Darwin-x86_64,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=darwin _GOARCH=amd64 make build_; \
	fi
rebuild-darwin-amd64: _pre-make _clean _build-darwin-amd64 _post-make
rebuild-all-darwin-amd64: _pre-make _clean-all _build-darwin-amd64 _post-make

build-linux-s390x: _pre-make _build-linux-s390x _post-make
_build-linux-s390x: _deps _fmt build-linux-s90x_
build-linux-s390x_:
	@if [ "" != "$(findstring Linux-s390x,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=linux _GOARCH=s390x make build_; \
	fi


install: _pre-make version-noarch _install _post-make
_install: _deps _fmt
	@echo "target: install"
	@printf "  ...installing dvdcli $(V_OS_ARCH)..."; \
		cd $(BASEDIR); \
		go clean -i $(VERSIONPKG); \
		go install $(GOFLAGS) $(LDFLAGS) ./version_info/ ./dvdcli/; \
		$(PRINT_STATUS); \
		if [ "$$EC" -eq "0" ]; then \
			FILE=$(GOPATH)/bin/dvdcli; \
			BYTES=$$($(STAT_FILE_SIZE)); \
			SIZE=$$(($$BYTES / 1024 / 1024)); \
			printf "\nThe dvdcli binary is $${SIZE}MB and located at:\n\n"; \
			printf "  $$FILE\n\n"; \
		fi

fmt: _pre-make _fmt _post-make

_fmt:
	@echo "target: fmt"
	@printf "  ...formatting dvdcli..."; \
		cd $(BASEDIR); \
		go fmt $(NV); \
		$(PRINT_STATUS)

fix: _pre-make _fix _post-make

_fix:
	@echo "target: fix"
	@printf "  ...fixing dvdcli..."; \
		cd $(BASEDIR); \
		go fmt $(NV); \
		$(PRINT_STATUS)

bench: _pre-make _bench _post-make

_bench: _install
	@echo "target: bench"
	@printf "  ...benchmarking dvdcli..."; \
		cd $(BASEDIR); \
		go test -run=NONE -bench=. $(GOFLAGS) $(NV); \
		$(PRINT_STATUS)

version:
	@echo SemVer: $(V_SEMVER)
	@echo RpmVer: $(V_RPM_SEMVER)
	@echo Binary: $(V_OS_ARCH)
	@echo Branch: $(V_BRANCH)
	@echo Commit: $(V_SHA_LONG)
	@echo Formed: $(V_BUILD_DATE)

version-noarch:
	@echo SemVer: $(V_SEMVER)
	@echo RpmVer: $(V_RPM_SEMVER)
	@echo Branch: $(V_BRANCH)
	@echo Commit: $(V_SHA_LONG)
	@echo Formed: $(V_BUILD_DATE)
	@echo

rpm:
	@echo "target: rpm"
	@printf "  ...building rpm $(V_ARCH)..."; \
		mkdir -p .deploy/latest; \
		rm -fr $(RPMBUILD); \
		mkdir -p $(RPMBUILD)/BUILD \
				 $(RPMBUILD)/RPMS \
				 $(RPMBUILD)/SRPMS \
				 $(RPMBUILD)/SPECS \
				 $(RPMBUILD)/SOURCES \
				 $(RPMBUILD)/tmp; \
		cp dvdcli.spec $(RPMBUILD)/SPECS/dvdcli.spec; \
		cd $(RPMBUILD); \
		setarch $(V_ARCH) rpmbuild -ba --quiet \
			-D "rpmbuild $(RPMBUILD)" \
			-D "v_semver $(V_RPM_SEMVER)" \
			-D "v_arch $(V_ARCH)" \
			-D "dvdcli $(CWD)/.bin/$(V_OS_ARCH)/dvdcli" \
			SPECS/dvdcli.spec; \
		$(PRINT_STATUS); \
		if [ "$$EC" -eq "0" ]; then \
			FILE=$$(readlink -f $$(find $(RPMBUILD)/RPMS -name *.rpm)); \
			DEPLOY_FILE=.deploy/$(V_OS_ARCH)/$$(basename $$FILE); \
			mkdir -p .deploy/$(V_OS_ARCH); \
			rm -f .deploy/$(V_OS_ARCH)/*.rpm; \
			mv -f $$FILE $$DEPLOY_FILE; \
			FILE=$$DEPLOY_FILE; \
			cp -f $$FILE .deploy/latest/dvdcli-latest-$(V_ARCH).rpm; \
			BYTES=$$($(STAT_FILE_SIZE)); \
			SIZE=$$(($$BYTES / 1024 / 1024)); \
			printf "\nThe dvdcli RPM is $${SIZE}MB and located at:\n\n"; \
			printf "  $$FILE\n\n"; \
		fi

rpm-linux-386:
	@if [ "" != "$(findstring Linux-i386,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=linux _GOARCH=386 make rpm; \
	fi

rpm-linux-amd64:
	@if [ "" != "$(findstring Linux-x86_64,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=linux _GOARCH=amd64 make rpm; \
	fi

rpm-linux-s390x:
	@if [ "" != "$(findstring Linux-s390x,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=linux _GOARCH=s390x make rpm; \
	fi
	
	
rpm-all: rpm-linux-386 rpm-linux-amd64 rpm-linux-s390x

deb:
	@echo "target: deb"
	@printf "  ...building deb $(V_ARCH)..."; \
		cd .deploy/$(V_OS_ARCH); \
		rm -f *.deb; \
		fakeroot alien -k -c --bump=0 *.rpm > /dev/null; \
		$(PRINT_STATUS); \
		if [ "$$EC" -eq "0" ]; then \
			FILE=$$(readlink -f $$(find .deploy/$(V_OS_ARCH) -name *.deb)); \
			DEPLOY_FILE=.deploy/$(V_OS_ARCH)/$$(basename $$FILE); \
			FILE=$$DEPLOY_FILE; \
			cp -f $$FILE .deploy/latest/dvdcli-latest-$(V_ARCH).deb; \
			BYTES=$$($(STAT_FILE_SIZE)); \
			SIZE=$$(($$BYTES / 1024 / 1024)); \
			printf "\nThe dvdcli DEB is $${SIZE}MB and located at:\n\n"; \
			printf "  $$FILE\n\n"; \
		fi

deb-linux-amd64:
	@if [ "" != "$(findstring Linux-x86_64,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=linux _GOARCH=amd64 make deb; \
	fi

deb-linux-s390x:
	@if [ "" != "$(findstring Linux-s390x,$(BUILD_PLATFORMS))" ]; then \
		env _GOOS=linux _GOARCH=s390x make deb; \
	fi

deb-all: deb-linux-amd64 deb-linux-s390x

test: _install
	@echo "target: test"
	@printf "  ...testing dvdcli ..."; \
		cd $(BASEDIR); \
		./test.sh; \
		$(PRINT_STATUS)

clean: _pre-make _clean clean-etc _post-make

_clean-go:
	@echo "target: clean"
	@printf "  ...go clean -i..."; \
		cd $(BASEDIR); \
		go clean $(GOFLAGS) -i $(NV); \
		$(PRINT_STATUS)

_clean-go-all:
	@echo "target: clean-all"
	@printf "  ...go clean -i -r..."; \
		cd $(BASEDIR); \
		go clean $(GOFLAGS) -i -r $(NV); \
		$(PRINT_STATUS)

_clean-etc:
	@printf "  ...rm -fr vendor..."; \
		cd $(BASEDIR); \
		rm -fr vendor; \
		$(PRINT_STATUS)
	@printf "  ...rm -fr .bin..."; \
		cd $(BASEDIR); \
		rm -fr .bin; \
		$(PRINT_STATUS)
	@printf "  ...rm -fr .deploy..."; \
		cd $(BASEDIR); \
		rm -fr .bin; \
		$(PRINT_STATUS)
	@printf "  ...rm -fr .rpmbuild..."; \
		cd $(BASEDIR); \
		rm -fr .bin; \
		$(PRINT_STATUS)
	@printf "  ...rm -f .bintray-*-filtered.json..."; \
		cd $(BASEDIR); \
		rm -f .bintray-*-filtered.json; \
		$(PRINT_STATUS)

_clean: _clean-go _clean-etc

_clean-all: _clean-go-all _clean-etc

clean-all: _pre-make _clean-all _post-make

rebuild: _pre-make _clean _build _post-make
rebuild-all: _pre-make _clean-all _build _post-make

reinstall: _pre-make _clean _install _post-make
reinstall-all: _pre-make _clean-all _build _post-make

retest: _pre-make _clean test _post-make
retest-all: _pre-make _clean-all test _post-make

.PHONY: all install build build_ build-all deps fmt fix clean version \
				rpm rpm-all deb deb-all test clean clean-all rebuild reinstall \
				retest clean-etc

.NOTPARALLEL: all test clean clean-all deps _deps fmt _fmt fix \
							pre-make _pre-make post-make _post-make build build-all_ \
							install rpm rebuild reinstall retest clean-etc
