# HF Infrastructure

The mission for this repository is to store all configuration, tooling, and
documentation for deploying Stackage.org and other Haskell Foundation-managed
infrastructure.

## Implementation Status (Stackage)

Stackage is deployed to a NixOS server.

The entrypoint for the server configuration is ./flake.nix.

There is a lot of work to do in order to make Stackage more reliable and robust.

## Participation

Yes, please! Please feel welcome to open issues reporting bugs, feature
requests, or questions. Pull requests are also welcome, though I recommend
creating an issue first.

### Git preferences

If possible, I (chreekat) prefer smaller commits. I usually end up doing an
interactive rebase to clean up my branch before merging. I believe in using
merge commits.

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

## Incidents

Public logs of infrastructure outages are tracked in issues labeled "incident".

https://github.com/commercialhaskell/stackage-server/issues?q=is%3Aissue%20label%3Aincident

Some issues were originally reported on stackage-server, so you'll find
incidents there, as well:

https://github.com/commercialhaskell/stackage-server/issues?q=is%3Aissue%20label%3Aincident
