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
      { sops.defaultSopsFile = ./test-sops-file.json;
        sops.age.keyFile = "/etc/test-age-key";
        environment.etc."test-age-key".source = ./test-age-key.txt;
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
          package =
            let
              stubServer = pkgs.writeScriptBin "stackage-server" ''
                #!${pkgs.python3}/bin/python3
                from http.server import HTTPServer, BaseHTTPRequestHandler
                class H(BaseHTTPRequestHandler):
                    def do_GET(self):
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(b"OK")
                HTTPServer(("", 3000), H).serve_forever()
              '';
            in pkgs.runCommand "stackage-server-dummy" {} ''
              mkdir -p $out/bin $out/run
              ln -s ${stubServer}/bin/stackage-server $out/bin/stackage-server
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

    # Verify caddy proxies requests to the stackage-server backend
    machine.wait_for_unit("caddy")
    try:
        machine.wait_for_unit("stackage-server")
    except Exception:
        print(machine.execute("systemctl status stackage-server")[1])
        print(machine.execute("journalctl -u stackage-server --no-pager")[1])
        raise
    machine.wait_for_open_port(3000)
    machine.wait_for_open_port(80)
    machine.succeed("curl -f -H 'Host: www.stackage.org' http://localhost/")
  '';
}
