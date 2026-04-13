{ self, inputs, pkgs }:

pkgs.testers.nixosTest {
  name = "stackage-test";
  nodes.machine = { ... }: {
    imports = [
      inputs.sops-nix.nixosModules.sops
      self.nixosModules.system-common
      self.nixosModules.monitoring
      self.nixosModules.stackage-curator
      self.nixosModules.hackage-metadata-refresh
      self.nixosModules.hackage-mirror
      self.nixosModules.stackage-server
      self.nixosModules.casa-server
      { sops.defaultSopsFile = ./empty-sops-file;
        sops.age.keyFile = "/dev/null";
        hardware.systemMemory = 4 * 1024 * 1024 * 1024; # 4 GB

        services.casa = {
          enable = true;
          tls.enable = false;
          package = pkgs.writeShellScriptBin "casa-server" "exit 0";
          curatorPackage = pkgs.writeShellScriptBin "casa-curator" "exit 0";
        };

        services.hackage-metadata-refresh = {
          enable = true;
          package = pkgs.writeShellScriptBin "all-cabal-tool" "exit 0";
        };

        services.stackage-server = {
          enable = true;
          tls.enable = false;
          package = pkgs.runCommand "stackage-server-dummy" {} ''
            mkdir -p $out/bin $out/run
            echo '#!/bin/sh' > $out/bin/stackage-server && chmod +x $out/bin/stackage-server
            echo '#!/bin/sh' > $out/bin/stackage-server-cron && chmod +x $out/bin/stackage-server-cron
            touch $out/run/config
          '';
        };
      }
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Verify casa service unit is created and enabled
    machine.succeed("systemctl cat casa")
    machine.succeed("systemctl is-enabled casa")

    # Check key configuration properties
    machine.succeed("systemctl show casa --property=User | grep -q casa")
    machine.succeed("systemctl show casa --property=Environment | grep -q PORT=3001")
    machine.succeed("systemctl show casa --property=Environment | grep -q AUTHORIZED_PORT=3002")
    machine.succeed("systemctl show casa --property=Environment | grep -q DBCONN=postgresql")
    machine.succeed("systemctl show casa --property=After | grep -q postgresql")

    # Verify casa-update service
    machine.succeed("systemctl cat casa-update")
    machine.succeed("systemctl is-enabled casa-update")
    machine.succeed("systemctl show casa-update --property=User | grep -q casa-update")

    # Verify hackage-metadata-refresh service
    machine.succeed("systemctl cat hackage-metadata-refresh")
    machine.succeed("systemctl is-enabled hackage-metadata-refresh")
    machine.succeed("systemctl show hackage-metadata-refresh --property=User | grep -q hackage-metadata-refresh")

    # Verify stackage-server service
    machine.succeed("systemctl cat stackage-server")
    machine.succeed("systemctl is-enabled stackage-server")
    machine.succeed("systemctl show stackage-server --property=User | grep -q stackage-server")

    # Verify stackage-update service and timer
    machine.succeed("systemctl cat stackage-update")

    # Verify health check timer
    machine.succeed("systemctl cat stackage-server-healthcheck.timer")
  '';
}
