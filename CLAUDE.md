# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Go through the binstubs in `bin/`, never `bundle exec` — the CI does the same, so
a command that works locally is the one CI runs. The tool shell runs in the `C`
locale, so prefix Ruby commands that read UTF-8 fixtures accordingly.

```bash
bundle install
bin/rake                                    # the default task: spec only
bin/rspec                                   # all specs, writes coverage/
bin/rspec spec/icinga2/config/diff_spec.rb  # one file
bin/rspec spec/icinga2/config/diff_spec.rb:42  # one example, by line
bin/rubocop
```

`.rspec` passes `--warnings`: Ruby warnings show up in spec output and are meant to
stay at zero.

Ruby is pinned to 3.4.10 by `mise.toml`, but the gemspec supports `>= 3.2.0` and
RuboCop targets 3.2 — do not use syntax newer than 3.2.

`icinga2-api-client` comes from a git source (`jbox-web/icinga2-api-client`), not
rubygems: a same-named gem from another author occupies the name. `Gemfile.lock`
is gitignored.

## Architecture

A Thor CLI (`exe/icinga-config` → `Icinga2::Config::CLI`) over the collaborators in
`lib/icinga2/config/`, autoloaded by Zeitwerk. `lib/icinga2/config.rb` holds no
`require` of its own any more — only what every file depends on: `UsageError`, the
`TYPES` catalogue and `DEFAULT_OBJECTS`.

**`TYPES` is the catalogue, `DEFAULT_OBJECTS` is the default — they are not the
same list and must not be merged back.** `TYPES` maps every *capturable* name to
its Icinga type (ten configuration types); `DEFAULT_OBJECTS` is the three a
snapshot captures when the fleet configures nothing. That split is what lets the
catalogue grow without changing what an existing installation writes. `objects:`
in `.icinga-config.yml` opts into the rest, validated by `Settings#objects`.

The names are the plural endpoint names, which is what the files on disk and
`--object` have always used; the type catalog in `icinga2-api-client` only answers
to the singular symbol and rejects the plural locally. `Comment` and `Downtime` are
deliberately absent from `TYPES`: they are runtime objects and would move between
two snapshots of a configuration nobody touched.

Zeitwerk autoloads everything under `lib/icinga2/config/`, set up at the **end** of
`config.rb` so a single `module Icinga2` opens the file. It uses
`for_gem_extension(Icinga2)`, not `for_gem`: the entry point is
`lib/icinga2/config.rb`, so the root is `lib/icinga2/` and `for_gem` maps
`config/store.rb` onto a top-level `Config::Store` — which made every constant in
the gem fail to resolve. `cli.rb` → `CLI` and `version.rb` → `VERSION` need
explicit inflections. Adding a file whose name does not match its constant breaks
loading, and `Zeitwerk::Loader.eager_load_all` is what surfaces it.

The pipeline is one direction: `Client` (env → API client) → `Snapshot` (fetch,
strip via `Attributes`, write JSON Lines) → `Store` (list/resolve/read) → `Diff`
(structural comparison) → `Reporter` (render). `Settings` feeds `Store` and
`Snapshot`; `Console` is a mixin used by `CLI` and `Reporter`; `Spinner` and
`StateReport` are mixins used by `CLI`; `ApiFailure` is consulted by `CLI` when the
transport raises.

`CLI` is kept under `Metrics/ClassLength` by extracting, not by raising the ceiling
again: `Spinner` and `StateReport` both came out of it that way. What belongs there
is the commands and their exit codes; rendering and terminal handling do not.

`Snapshot#take` yields each type just before fetching it. That callback is the only
thing connecting the fetch to the terminal — `Snapshot` itself knows nothing about
whether anything is watching, which is why the spinner lives in `Spinner`/`CLI`.

### Invariants that are load-bearing

**Exit codes are a contract.** 0 = no difference, 1 = differences detected, 2 =
usage error. `UsageError` exists precisely so a usage error never exits 1 — a cron
job must not mistake a missing snapshot for a configuration change. Anything the
caller can fix raises `UsageError`; the CLI catches it in each command and exits 2.

**A transport failure is a usage error too.** `snapshot` and `state` rescue
`Icinga2::API::Error` alongside `UsageError` and run it through `ApiFailure.wrap`,
which turns it into a `UsageError` naming what to check — `ICINGA_API_HOST` and the
port for a connection failure, `ICINGA_API_USER`/`ICINGA_API_PASS` for a 4xx. Left
alone it would escape as a backtrace on a status that is neither 0, 1 nor 2, which
a cron job cannot classify. `ApiFailure::HINTS` is an ordered list walked with
`is_a?`, never a Hash keyed by class: `NotFound < ClientError`, so a lookup would
miss the subclass and the reverse order would report a missing object as a
credentials problem. Appending the original class and message is deliberate and
safe — the credentials travel in a header, never in the URL these messages quote.

**Byte-identical snapshots.** Two snapshots of an unchanged configuration must
compare equal line by line. Three mechanisms guarantee it, and breaking any one
floods every diff with noise: `Attributes.strip` removes what moves on its own,
`Snapshot#sort_deep` sorts keys at every level, and objects are sorted by
`Diff::NAME` (`__name`) before writing.

**Stripping is deliberate, never a bug.** Runtime state (check results, states,
notification counters, acknowledgements, flapping, timings) and source-location
line numbers are dropped at fetch time. The `state` command exists to expose what
snapshots leave out — do not "fix" a missing runtime attribute by unstripping it.
`STATE_FAMILY` is a regex rather than a list because host and service state members
differ and a hand-kept list silently misses one.

**Fleet-specific volatility lives in config, not code.** `volatile_vars` in
`.icinga-config.yml` names the `vars.*` entries that move on a given installation.
The gem ships none — hardcoding an installation's names here is the mistake the
file prevents.

**Atomic writes.** `Snapshot#write` writes to `.<object>.jsonl.part` then moves it
into place; a failure discards partials and `rmdir`s the directory (only succeeds
if empty, so partially-fetched snapshots keep what they got). An empty leftover
directory would become `latest` and the next diff would resolve to it.

**`diff` compares the intersection, and announces the rest.** Two snapshots taken
with different `objects:` lists are compared on `store.types(old) & store.types(new)`,
with a `skipped:` line naming what only one side carries. Failing instead would make
the first diff after any widening exit 2 with nothing having changed in the
configuration. Two things keep that from becoming a silent lie: the skip is always
printed, and a `--object` naming a type one side lacks stays a `UsageError` — it was
asked for explicitly. `--object` is validated against `TYPES`, never against the
configured list, so a type dropped from `objects:` since a snapshot was taken stays
diffable.

**Fetching goes through the generic collection.** `Snapshot#fetch` calls
`client.objects(TYPES.fetch(name)).all { |attrs| attrs }`, never `api.get` with a
hand-built URL: the catalog resolves the endpoint and rejects an unknown type
before a request goes out, and the collection flips to POST on its own when the
query outgrows the request line. The identity block is load-bearing — without it
the collection builds `Host`/`Service` objects, whose `to_hash` symbolises every
key, and the whole pipeline downstream reads string keys.

**Requiring fylla changes Thor for the whole application.** `require 'fylla'` sits
above `require 'thor'` in `cli.rb` because it prepends into `Thor::Option` and
`Thor::Arguments`, and an option declared before the require would silently keep
Thor's defaults. The visible consequence: `type: :array` options now accept a
comma-separated form, so `--object hosts,services` works alongside Thor's
`--object hosts services` — verified, and `--object hosts,bogus` still exits 2.
`Fylla.load('icinga-config')` runs at load time of `cli.rb`, not in
`exe/icinga-config`, so that `CLI.start` behaves identically when driven directly
as the specs do. The executable name is what the generated script drives; fylla
raises rather than emitting an inert script if it is missing.

**Never `Whirly.start { ... }` — always start/stop around the work.** Whirly
returns early *without calling its block* when the stream is not a terminal
(`whirly.rb:143`, verified). Putting the fetch inside the block would mean a cron
run takes no snapshot at all and still exits 0. `Spinner#with_spinner` starts it,
yields outside it, and stops in an `ensure`, so the work runs either way, its
return value is the block's, and `UsageError`/`Icinga2::API::Error` reach the CLI's
rescue. It also passes `stream: $stdout` on every call: whirly's default captures
`$stdout` once at load time, so a replaced `$stdout` — every spec here — would be
ignored. Colour comes from `Console#color?` so `NO_COLOR` covers paint too.

**Credentials never touch ARGV.** `Client` reads `ICINGA_API_*` from `ENV` with
defaults in `Client::DEFAULTS`, so `ps` cannot expose them. Do not add CLI options
for them. The gem does not load a `.env` — that is the caller's business.

**Settings precedence** is environment, then `.icinga-config.yml` (looked up from
the working directory upwards), then a generic default. `Store` is built from
`Settings#snapshot_dir`, resolved against the caller's directory — never `__dir__`,
which would point inside the installed gem.

**Truncation is announced.** `Reporter` caps object detail at `DETAIL_LIMIT` (20)
and always prints how many were hidden plus the `--all` hint; a silent cap reads as
"that was everything".

**Legacy detection.** `Store#read` recognises a `.json` file from the predecessor
bash tool and raises a `UsageError` explaining it, instead of failing on a JSON
parse error.

## Testing

Every file under `lib/` has a spec and line coverage is 100%. Nothing talks to a
real master: `snapshot_spec` and `cli_spec` stub the API with
`instance_double(Icinga2::API::Client)` / `Interface` / `Hosts` / `Services`.
`Icinga2::API::Host` cannot be a verifying double — its attribute readers and
`name` go through `method_missing` — so `cli_spec` uses a plain double there, with
the cop disabled on that line only.

Stubs of `Objects#all` must apply the builder block (`stub_all` in `snapshot_spec`
does; `receive(:all) { |&builder| … }`). A stub returning a canned array never calls
it, and the identity block — the one thing keeping the keys as strings — would sit
uncovered while the suite stayed green.

What the transport still does not prove: `client_spec` asserts the arguments handed
to `Icinga2::API::Client.new`, not that a request succeeds. No HTTP is exercised, so
a faraday-level or certificate-level breakage remains invisible to the suite.

`cli_spec` drives real `CLI.start(argv)` calls, captures `$stdout`/`$stderr` and
reads the status off the `SystemExit` — that is what pins the 0/1/2 contract. Point
`ICINGA_SNAPSHOT_DIR` at a `Dir.mktmpdir` to steer the CLI at a scratch directory,
as it does. `console_spec` and `reporter_spec` swap `$stdout` for a StringIO rather
than using the `output(...).to_stdout` matcher, because `Console#color?` asks
`$stdout.tty?` and the matcher installs an object they cannot control;
`RSpec/ExpectOutput` is excluded for those two files.

Filesystem specs use `Dir.mktmpdir`; `settings_spec` wraps it in `File.realpath`
because macOS `/var` is a symlink to `/private/var` and the discovered root would
otherwise compare unequal.

`version.rb` is filtered out of the coverage report — not untested, unmeasurable:
the `gemspec` directive in the Gemfile makes Bundler `require_relative` it while
loading the gemspec, long before SimpleCov starts, so it would sit at a permanent
and misleading 0%. `version_spec` covers it regardless.

The suite has been mutation-checked: breaking `EXIT_USAGE`, `exit EXIT_DIFF`,
`DETAIL_LIMIT`, the truncation notice, `names_only`'s `difference?`, the CA-over-
insecure precedence in `ssl_options`, the `NO_COLOR` check, the `Array` branch of
`sort_deep`, the empty-response guard, the `NotFound`-before-`ClientError` order in
`ApiFailure::HINTS`, the `Icinga2::API::Error` rescue, `TYPES` entries, and the
identity builder each makes a spec fail. Keep that true — a test that survives its
invariant being deleted is only decorating the percentage. Restore mutated files
from a copy, not `git checkout`: this work is often uncommitted, and a checkout
silently reverts it to HEAD instead of undoing the mutation.

SimpleCov starts at the top of `spec_helper`, before the library is required —
moving it below the `require` would count every file loaded at require time as
zero-covered. It writes `coverage/coverage.json` (published to qlty by CI) and
`coverage/index.html` (for reading locally). SimpleCov 1.x bundles both formatters;
the separate `simplecov-html` / `simplecov_json_formatter` gems that 0.22 setups
declare are not needed here.

CI (`.github/workflows/ci.yml`) runs a RuboCop job on 3.2 and an RSpec matrix over
MRI 4.0/3.4/3.3/3.2, publishing coverage from the 3.4 entry only. It needs a
`QLTY_COVERAGE_TOKEN` repository secret. `bin/rake` runs the specs only, so RuboCop
is a separate command locally as it is a separate job in CI.

The binstubs are kept RuboCop-clean rather than excluded from it, so regenerating
them with `bundle binstubs` reintroduces double-quoted strings and fails the lint —
restyle them instead of adding a `bin/*` exclusion.
