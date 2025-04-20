{
  nixConfig.substituters = [
    "https://cache.nixos.org"
    "https://stackage-infrastructure.cachix.org"
  ];
  nixConfig.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "stackage-infrastructure.cachix.org-1:R3E1FYE8IKCNbUWCvVhsnlLJ4FC6onEQLhQX2kY0ufQ="
  ];

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-2311.url = "github:nixos/nixpkgs/nixos-23.11";
    # LTS 15.6 (GHC 8.8.3)
    nixpkgs-2009.url = "github:nixos/nixpkgs/nixos-20.09";
    sops-nix.url = "github:Mic92/sops-nix";
    disko.url = "github:nix-community/disko";
    haskell-certification.url = "github:serokell/haskell-certification";
    stackage-server.url = "github:commercialhaskell/stackage-server";
  };
  outputs = inputs@{ self, ... }: {
    nixosModules.nix-hygiene = ./shared/nix-hygiene.nix;
    nixosModules.hf-cert-1 = {
      imports = [
        ./hf-cert-1
        self.nixosModules.nix-hygiene
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
        inputs.haskell-certification.nixosModules.default
      ];
    };
    nixosModules.stackage-builder = { ... }: {
      imports = [
        # Change this to a flake-defined nixosModule as well?
        ./stackage-builder/configuration.nix
        self.nixosModules.hackage-metadata-refresh
        self.nixosModules.hackage-mirror
        self.nixosModules.stackage-server
        self.nixosModules.casa-server
        self.nixosModules.stackage-curator
        self.nixosModules.nix-hygiene
        inputs.sops-nix.nixosModules.sops
        {
          security.acme.acceptTerms = true;
          # FIXME we need a centralized address for this.
          security.acme.defaults.email = "bryan@haskell.foundation";
        }
        { services.fail2ban.enable = true; }
        # This could be a *lot* bigger, but it probably makes more sense to
        # forward it to a central log server (even though we don't have one
        # yet). I don't know how well journald actually handles huge logs
        { services.journald.extraConfig = "SystemMaxSize=48GB"; }
      ];
    };

    devShells.x86_64-linux.default = inputs.nixpkgs.legacyPackages.x86_64-linux.mkShell {
      buildInputs = [ inputs.sops-nix.packages.x86_64-linux.default ];
    };

    ##
    ## STACKAGE CURATOR
    ##

    nixosModules.stackage-curator = ./stackage-builder/nixos-modules/stackage-curator.nix;

    ##
    ## HACKAGE METADATA REFRESH
    ##

    # FIXME extract from flake.nix, as above

    # This overlay is only used to define the all-cabal-tool package. It's only
    # exposed because it can be.
    overlays.all-cabal-tool =
      let
        myPackage = "all-cabal-tool";
        hsOverlay = pkgs: self: super: {
          ${myPackage} = pkgs.haskell.lib.buildStackProject {
            name = myPackage;
            src = builtins.fetchGit {
              url = "https://github.com/commercialhaskell/${myPackage}.git";
              rev = "189c8fc25859c59808974a5a4b6d1cf7526bda1a";
            };
            ghc = pkgs.haskell.compiler.ghc963;
            buildInputs = [ pkgs.zlib ];
            patches = [ ./stackage-builder/all-cabal-tool_lts-22.4.patch ];
          };
        };
      in final: prev: {
        myHaskellPackages = prev.haskellPackages.override {
          overrides = hsOverlay final;
        };
      };
    packages.x86_64-linux.all-cabal-tool =
      let
        myPkgs = import inputs.nixpkgs-2311 {
          system = "x86_64-linux"; overlays = [ self.overlays.all-cabal-tool ];
        };
      in myPkgs.myHaskellPackages.all-cabal-tool;

    # This module wraps all-cabal-tool into a systemd service.
    nixosModules.hackage-metadata-refresh = { lib, config, pkgs, ... }:
      let
        name = "hackage-metadata-refresh";
        mkRuntimeSecrets = keys:
          lib.attrsets.genAttrs
            (map (k: "${name}/runtime/${k}") keys)
            (_: { owner = name; });
      in {
        programs.ssh.knownHostsFiles = [ ./github_host_keys ];
        users.groups.${name} = {
          gid = 1003;
        };
        users.users.${name} = {
          uid = 1003;
          isNormalUser = true;
          group = name;
          home = "/home/${name}";
          createHome = true;
        };
        sops.secrets = {
          "${name}/ssh_key" = {
            owner = name;
            path = "/home/${name}/.ssh/id_rsa";
          };
        } // mkRuntimeSecrets
          [ "aws_access"
            "aws_secret"
            "s3_bucket"
          ];
        systemd.services.${name} = {
          description = "Refresh hackage metadata";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            User = name;
            Restart = "on-failure";
            RestartSec = 1;
            LoadCredential = "creds:/run/secrets/${name}/runtime";
            # sop.secrets provides ~/.gnupg/secring.gpg, but with wrong
            # permissions. Fix before starting the unit.
            ExecStartPre = [
              "+${pkgs.coreutils}/bin/chmod 700 /home/${name}/.gnupg"
              "+${pkgs.coreutils}/bin/chown ${name}:${name} /home/${name}/.gnupg"
            ];
          };
          script = ''
              ${self.packages.x86_64-linux.all-cabal-tool}/bin/all-cabal-tool \
                --username all-cabal-tool \
                --email michael+all-cabal-files@snoyman.com \
                --gpg-sign D6CF60FD \
                --s3-bucket "$(< "$CREDENTIALS_DIRECTORY/creds_s3_bucket")" \
                --aws-access-key "$(< "$CREDENTIALS_DIRECTORY/creds_aws_access")" \
                --aws-secret-key "$(< "$CREDENTIALS_DIRECTORY/creds_aws_secret")"
          '';
          path = [ pkgs.git pkgs.gnupg pkgs.openssh ];
        };
    };

    ##
    ## HACKAGE MIRROR
    ##

    # FIXME extract from flake.nix, as above

    # Same as the other overlay, this is only exposed because it can be. It's
    # just used to define the hackage-mirror-tool package.
    overlays.hackage-mirror-tool =
      let
        myPackage = "hackage-mirror-tool";
        hsOverlay = pkgs: self: super:
          let
            hackageMirrorRepo = {
              url = "https://github.com/commercialhaskell/${myPackage}.git";
              rev = "aca12a2f66d8fe29012982e7cd95ea4283e02193";
            };
          in {
            # Jailbreak to get around my amazonka>2.0 failsafe
            ${myPackage} = pkgs.haskell.lib.compose.doJailbreak (self.callCabal2nix
              myPackage
              (builtins.fetchGit hackageMirrorRepo)
              {});
          };
      in final: prev: {
        myHaskellPackages = prev.haskellPackages.override {
          overrides = hsOverlay final;
        };
      };
    packages.x86_64-linux.hackage-mirror-tool =
      let
        myPkgs = import inputs.nixpkgs-2311 {
          system = "x86_64-linux"; overlays = [ self.overlays.hackage-mirror-tool ];
        };
      in myPkgs.myHaskellPackages.hackage-mirror-tool;

    # Make a service out of hackage-mirror-tool. It doesn't have a loop built
    # in, which means we get to control it with systemd (which I appreciate).
    nixosModules.hackage-mirror = import ./stackage-builder/nixos-modules/hackage-mirror.nix {
      hackage-mirror-tool-app = self.packages.x86_64-linux.hackage-mirror-tool;
    };

    ##
    ## STACKAGE SERVER
    ##
    ##
    ## Comprised of stackage-server-update and stackage-server itself.

    nixosModules.stackage-server = import ./stackage-builder/nixos-modules/stackage-server.nix {
      stackage-update-uid = 1005;
      stackage-uid = 1006;
      stackage-server-app = inputs.stackage-server.packages.x86_64-linux.default;
    };

    # Expose this mainly so I can roll it up in cachix-push.sh. I should
    # probably do this from that repo itself, though...
    packages.x86_64-linux.stackage-server = inputs.stackage-server.packages.x86_64-linux.default;

    ##
    ## CASA SERVER
    ##

    # FIXME extract from flake.nix, as above

    # Just used to define the casa package.
    overlays.casa =
      let
        myPackage = "casa";
        hsOverlay = pkgs: self: super: {
          ${myPackage} = pkgs.haskell.lib.buildStackProject {
            name = myPackage;
            src = builtins.fetchGit {
              url = "https://github.com/commercialhaskell/${myPackage}.git";
              rev = "9ce3ae6653120ca00b898c193ee5c9955b697d34";
            };
            ghc = pkgs.haskell.compiler.ghc8107;
            buildInputs = [ pkgs.zlib pkgs.git pkgs.postgresql ];
            # FIXME: Shifting the tests to lts-15.6 proved too much work, so
            # I've disabled them.
            checkPhase = "";
          };
        };
      in final: prev: {
        myHaskellPackages = prev.haskellPackages.override {
          overrides = hsOverlay final;
        };
      };
    packages.x86_64-linux.casa =
      let
        myPkgs = import inputs.nixpkgs-2009 {
          system = "x86_64-linux"; overlays = [ self.overlays.casa ];
        };
      in myPkgs.myHaskellPackages.casa;

    # Just used to define the curator package. This package has both "curator",
    # used by curators manually, and "casa-curator", which I'll set up in the
    # casa-server nixos module below.
    overlays.curator =
      let
        myPackage = "curator";
        hsOverlay = pkgs: self: super: {
          ${myPackage} = pkgs.haskell.lib.buildStackProject {
            name = myPackage;
            src = builtins.fetchGit {
              url = "https://github.com/commercialhaskell/${myPackage}.git";
              rev = "558215d639561301a0069dc749896ad3e71b5c24";
            };
            patches = [ ./stackage-builder/curator_hackage-server-T1023.patch ];
            ghc = pkgs.haskell.compiler.ghc947;
            buildInputs = [ pkgs.zlib pkgs.openssl pkgs.sqlite ];
            # FIXME: Tests have a 'Not in scope' compile error!
            checkPhase = "";
          };
        };
      in final: prev: {
        myHaskellPackages = prev.haskellPackages.override {
          overrides = hsOverlay final;
        };
      };
    packages.x86_64-linux.curator =
      let
        myPkgs = import inputs.nixpkgs-2311 {
          system = "x86_64-linux"; overlays = [ self.overlays.curator ];
        };
      in myPkgs.myHaskellPackages.curator;

    nixosModules.casa-server = import ./stackage-builder/nixos-modules/casa-server.nix {
      casa-uid = 1007;
      casa-updater-uid = 1008;
      casa-app = self.packages.x86_64-linux.casa;
      curator-app = self.packages.x86_64-linux.curator;
    };

    checks."x86_64-linux".test-vm = inputs.nixpkgs.legacyPackages."x86_64-linux".callPackage ./test-os.nix { inherit self; };
  };
}
