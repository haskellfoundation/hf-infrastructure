{ self, inputs, pkgs }:

pkgs.nixosTest {
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
      }
    ];
  };

  testScript = ''
    machine.wait_for_open_port(22)
  '';
}
