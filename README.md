# HF Infrastructure

The mission for this repository is to store all configuration, tooling, and
documentation for deploying Stackage.org and other Haskell Foundation-managed
infrastructure.

## Status (Stackage)

Stackage is deployed to a NixOS server.

The entrypoint for the server configuration is ./flake.nix.

There is a lot of work to do in order to make Stackage more reliable and robust.
The maintainers will be documenting and implementing that work in the coming
months.

## Tooling

### ./redeploy.sh

A wrapper around `nixos-rebuild` that provides some measure of deployment
tracking.

### ./cachix-push.sh

A wrapper that pushes all component packages to a Cachix cache.

## Participation

Yes, please! Please feel welcome to open issues reporting bugs, feature
requests, or questions. Pull requests are also welcome, though I recommend
creating an issue first.

### Contact

This repository: https://github.com/haskellfoundation/hf-infrastructure

Forum: https://discourse.haskell.org/

Chat: via the Matrix network at https://matrix.to/#/#haskell-stack:matrix.org

### Related repositories

* [Snapshot curation](https://github.com/commercialhaskell/stackage)
* [Stackage server app](https://github.com/commercialhaskell/stackage-server)

### Conduct

As a Haskell Foundation project, the maintainers follow the [Guidelines for
Respectful
Communication](https://haskell.foundation/guidelines-for-respectful-communication/),
and recommend the same for all other project participants.

## Maintainers

This repo is a work of the [Haskell Foundation](https://haskell.foundation).

The initial version was implemented by Bryan Richter (@chreekat) in his capacity
as the Haskell Foundation's DevOps Engineer.
