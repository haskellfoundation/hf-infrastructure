{ self, pkgs }:

pkgs.nixosTest {
  name = "stackage-test";
  nodes.machine = { ... }: {
    imports = [
      self.nixosModules.stackage-builder
      { sops.defaultSopsFile = ./empty-sops-file;
        sops.age.keyFile = "/dev/null";
      }
    ];
    services.fwupd.enable = true;
  };

  testScript = ''
    machine.wait_for_open_port(22)
  '';
}
