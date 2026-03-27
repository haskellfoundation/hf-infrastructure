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
  '';
}
