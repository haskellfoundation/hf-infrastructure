# Edit the test sops file (dummy secrets for VM tests)
edit-test-secrets:
    SOPS_AGE_KEY_FILE=test-age-key.txt sops test-sops-file.json

test:
    nix flake check
