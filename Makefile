# =============================================================================
#  LexOS — raccourcis de construction
# =============================================================================

SHELL       := /bin/bash
FLAVOUR     ?= standard
ARCH        ?= amd64
ISO         := $(firstword $(wildcard *.iso))
QEMU_RAM    ?= 3072

.DEFAULT_GOAL := help

# -----------------------------------------------------------------------------
.PHONY: help
help: ## Affiche cette aide
	@printf '\n\033[38;5;208mLexOS\033[0m — cibles disponibles\n\n'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[38;5;215m%-14s\033[0m %s\n", $$1, $$2}'
	@printf '\nVariables : FLAVOUR=%s  ARCH=%s\n\n' "$(FLAVOUR)" "$(ARCH)"

.PHONY: check
check: ## Vérifie que l'environnement de build est complet
	@sudo ./build.sh --check

.PHONY: build
build: ## Construit l'ISO (FLAVOUR=minimal|standard|dev|full)
	@sudo ./build.sh --flavour $(FLAVOUR) --arch $(ARCH)

.PHONY: minimal standard dev full
minimal:  ## ISO sans bureau (console seule, ~700 Mio)
	@sudo ./build.sh --flavour minimal
standard: ## ISO bureau XFCE + navigateur (défaut, ~2,5 Gio)
	@sudo ./build.sh --flavour standard
dev:      ## ISO standard + atelier développeur (~4 Gio)
	@sudo ./build.sh --flavour dev
full:     ## Tout : bureautique, multimédia, création (~6 Gio)
	@sudo ./build.sh --flavour full

.PHONY: clean
clean: ## Supprime les artefacts de build (garde l'ISO)
	@sudo lb clean --purge || true
	@rm -f build.log
	@rm -f config/package-lists/zz-flavour-*.list.chroot
	@rm -f config/includes.chroot/etc/lexos/build.conf
	@rm -rf config/includes.chroot/usr/share/lexos/branding
	@printf 'Nettoyé.\n'

.PHONY: distclean
distclean: clean ## Supprime aussi les ISO et les sommes de contrôle
	@rm -f ./*.iso ./*.iso.sha256 ./*.contents ./*.files ./*.packages
	@printf 'Tout est propre.\n'

.PHONY: test
test: ## Démarre la dernière ISO dans QEMU (BIOS)
	@test -n "$(ISO)" || { echo "Aucune ISO. Lance d'abord : make build"; exit 1; }
	@echo "Démarrage de $(ISO) dans QEMU…"
	@qemu-system-x86_64 -m $(QEMU_RAM) -smp 2 -enable-kvm \
		-vga virtio -display gtk,gl=on \
		-cdrom "$(ISO)" -boot d

.PHONY: test-uefi
test-uefi: ## Démarre la dernière ISO dans QEMU (UEFI)
	@test -n "$(ISO)" || { echo "Aucune ISO. Lance d'abord : make build"; exit 1; }
	@test -r /usr/share/OVMF/OVMF_CODE.fd || { echo "Installe le paquet ovmf"; exit 1; }
	@qemu-system-x86_64 -m $(QEMU_RAM) -smp 2 -enable-kvm \
		-vga virtio -display gtk,gl=on \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
		-cdrom "$(ISO)" -boot d

.PHONY: usb
usb: ## Grave l'ISO sur une clé USB — DEVICE=/dev/sdX obligatoire
	@test -n "$(ISO)"    || { echo "Aucune ISO trouvée."; exit 1; }
	@test -n "$(DEVICE)" || { echo "Usage : make usb DEVICE=/dev/sdX"; exit 1; }
	@echo ""
	@echo "  ⚠  TOUT le contenu de $(DEVICE) va être effacé."
	@lsblk -dno NAME,SIZE,MODEL "$(DEVICE)" 2>/dev/null || true
	@echo ""
	@read -r -p "  Taper OUI pour confirmer : " a; [ "$$a" = "OUI" ] || { echo "Annulé."; exit 1; }
	@sudo dd if="$(ISO)" of="$(DEVICE)" bs=4M status=progress oflag=sync
	@sync
	@printf '\nClé prête. Démarre dessus pour essayer LexOS en mode démo.\n'

.PHONY: lint
lint: ## Analyse les scripts avec shellcheck
	@command -v shellcheck >/dev/null || { echo "Installe shellcheck"; exit 1; }
	@shellcheck -S warning \
		build.sh auto/config auto/build auto/clean \
		config/hooks/normal/*.hook.chroot \
		config/includes.chroot/usr/bin/* \
		config/includes.chroot/etc/profile.d/lexos.sh \
		&& printf 'shellcheck : rien à signaler.\n'

.PHONY: preview
preview: ## Rend les visuels SVG en PNG dans ./preview
	@./tools/render-branding.sh preview
