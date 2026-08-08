.PHONY: build-android build-android-debug build-android-release

MODE ?= debug
APP_ENV = $(if $(filter release,$(MODE)),production,development)

build-android:
	@if [ "$(MODE)" != "debug" ] && [ "$(MODE)" != "release" ]; then \
		echo 'MODE must be debug or release.' >&2; \
		exit 1; \
	fi
	@if [ -z "$(BACKEND_BASE_URL)" ]; then \
		echo 'BACKEND_BASE_URL is required.' >&2; \
		exit 1; \
	fi
	@if [ "$(MODE)" = "release" ]; then \
		case "$(BACKEND_BASE_URL)" in \
			https://*) ;; \
			*) echo 'Release BACKEND_BASE_URL must use https://.' >&2; exit 1 ;; \
		esac; \
	fi
	flutter build apk --$(MODE) \
		--dart-define=APP_ENV=$(APP_ENV) \
		"--dart-define=BACKEND_BASE_URL=$(BACKEND_BASE_URL)"

build-android-debug:
	$(MAKE) build-android MODE=debug

build-android-release:
	$(MAKE) build-android MODE=release
