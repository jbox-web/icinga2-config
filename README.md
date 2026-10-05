# icinga2-config

[![GitHub license](https://img.shields.io/github/license/jbox-web/icinga2-config.svg)](https://github.com/jbox-web/icinga2-config/blob/master/LICENSE)
[![GitHub release](https://img.shields.io/github/release/jbox-web/icinga2-config.svg)](https://github.com/jbox-web/icinga2-config/releases/latest)
[![CI](https://github.com/jbox-web/icinga2-config/workflows/CI/badge.svg)](https://github.com/jbox-web/icinga2-config/actions)
[![Maintainability](https://qlty.sh/gh/jbox-web/projects/icinga2-config/maintainability.svg)](https://qlty.sh/gh/jbox-web/projects/icinga2-config)
[![Code Coverage](https://qlty.sh/gh/jbox-web/projects/icinga2-config/coverage.svg)](https://qlty.sh/gh/jbox-web/projects/icinga2-config)

Snapshot, diff and inspect the live configuration of an Icinga 2 master.

The problem it solves: after reloading a master, "did that change only what I
meant it to?" is not answerable from the configuration files — apply rules
instantiate into thousands of objects. This fetches what Icinga actually built,
strips the attributes that move on their own, and compares two of those.

## Install

Not published on rubygems. In a `Gemfile`:

```ruby
gem 'icinga2-config', git: 'https://github.com/jbox-web/icinga2-config'
```

## Usage

```bash
icinga-config snapshot                 # fetch the live configuration into snapshots/<timestamp>/
icinga-config diff                     # compare the two most recent snapshots
icinga-config diff OLD NEW             # compare two named snapshots (also accepts `latest` / `prev`)
icinga-config diff --names-only        # compare object names only
icinga-config diff --object hosts      # restrict to one object type (see below)
icinga-config diff --all               # detail every changed object instead of the first 20
icinga-config diff --object hosts,services  # or space-separated, both work
icinga-config list                     # list available snapshots
icinga-config state HOST [SERVICE]     # runtime state: state, attempts, plugin output, command
icinga-config completion zsh           # print the shell completion script (or bash)
```

## Shell completion

```bash
# zsh, into a directory on your $fpath
icinga-config completion zsh > ~/.zsh/completions/_icinga-config

# bash
icinga-config completion bash > ~/.local/share/bash-completion/completions/icinga-config
```

The script is generated from the commands and options themselves, so it never
drifts from them — regenerate it after upgrading rather than editing it.

`diff` exits **0** when there is no difference, **1** when differences are
detected, and **2** on a usage or input error. A usage error never exits 1, so a
cron job cannot mistake a missing snapshot for a configuration change.

A master that is unreachable, or credentials it rejects, exits **2** as well, with
a message naming what to check rather than a Ruby backtrace:

```
Cannot reach the Icinga 2 API at https://icinga.example.net:5665. Check
ICINGA_API_HOST and ICINGA_API_PORT, and that the master is running.
(ConnectionFailed: Failed to open TCP connection)
```

It reports which attribute changed and on how many objects before showing the
detail:

```
services
  ~ 287 changed
      vars.notification_period                 287 objects
    ad-lb01.mar02!Load
      - vars.notification_period: "24x7" -> nil
```

`snapshot` fetches one object type after another and says nothing until the last
one is in, so it shows a spinner naming the type in flight. It draws only on a
terminal: redirected to a file or run from cron, the output is exactly what it was
before, with no escape sequence in it.

**`snapshot`/`diff` answer what the configuration declares; `state` answers what
a check returns.** The first cannot answer the second: the runtime attributes are
stripped on purpose, because they change on every execution and would drown any
real difference.

## Configuration

Credentials and endpoint come from the environment:

| Variable | Role | Default |
|---|---|---|
| `ICINGA_API_HOST` | master hostname | `icinga.example.net` |
| `ICINGA_API_PORT` | API port | `5665` |
| `ICINGA_API_USER` | API user | `root` |
| `ICINGA_API_PASS` | API password | `pass` |
| `ICINGA_API_SCHEME` | `http` or `https` | `https` |
| `ICINGA_API_INSECURE` | `1` to skip TLS verification | `1` |
| `ICINGA_API_CACERT` | CA bundle for the Icinga internal CA | none |
| `ICINGA_SNAPSHOT_DIR` | snapshot directory | see below |

They are handed to the HTTP client directly, never as command-line arguments
where `ps` would expose them to every local account. Loading them from a `.env`
is the caller's business — this gem deliberately does not.

What belongs to a fleet rather than to the tool goes in `.icinga-config.yml`,
looked up from the working directory upwards:

```yaml
# where snapshots are written, relative to this file unless absolute
snapshot_dir: snapshots

# `vars.*` entries that are volatile on this installation. No generic default
# can know them: this one is a whole Host object copied into every VM service.
volatile_vars:
  - see_esx_host

# which object types to capture. Defaults to hosts, services and notifications.
objects:
  - hosts
  - services
  - notifications
  - timeperiods
```

Precedence is environment, then this file, then a generic default.

### Which object types can be captured

`hosts`, `services`, `notifications`, `hostgroups`, `servicegroups`, `usergroups`,
`users`, `timeperiods`, `dependencies`, `scheduleddowntimes`.

Configuration types only. Comments and downtimes are **not** capturable: an
operator creates them and a scheduled rule keeps creating them, so they would move
between two snapshots of a configuration nobody touched — the noise this tool
exists to remove. `state` remains the way to look at what is happening right now.

Widening the list does not invalidate what you already have: `diff` compares the
types both snapshots carry and prints a `skipped:` line for the rest, so the first
comparison after a change still works and tells you what it could not compare.
Naming one of those types explicitly with `--object` is an error rather than a
silent "no diff", since you asked for it. `list` shows what each snapshot actually
carries, which is not necessarily what is configured today.

## Snapshot format

JSON Lines: one object per line, keys sorted at every level, so two snapshots of
an unchanged configuration are identical byte for byte. Stripped at fetch time:
check results and states, notification counters, operator acknowledgements,
flapping and downtime counters, execution timings, and the line numbers of the
source location — which move whenever an unrelated line is added above an object.

## Development

```bash
bundle install
bin/rspec              # the whole suite, writes coverage/
bin/rubocop
bin/rake               # the default task: specs only
```

Every file under `lib/` is covered. The API is stubbed, never contacted: the specs
prove what is sent to the client and what is done with what comes back, not that a
request succeeds. A Faraday-level or certificate-level breakage stays invisible to
the suite, and only real use catches it.

## License

MIT
