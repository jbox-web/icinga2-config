# frozen_string_literal: true

require 'whirly'
require 'paint'

module Icinga2
  module Config
    # A spinner for the long silent stretch of a snapshot, where nothing is
    # printed until every object type has been fetched.
    #
    # Sits next to Console rather than inside Snapshot: fetching has no business
    # knowing whether anything is watching.
    module Spinner
      include Console

      # Runs the work with a spinner, handing the block a callback that updates
      # the status line.
      #
      # Deliberately NOT `Whirly.start { ... }`: whirly returns early — without
      # calling the block at all — when the stream is not a terminal, so the block
      # form would take no snapshot whatsoever under cron and still exit 0. The
      # work is started and stopped around instead, so it runs either way, its
      # return value is the block's, and its exceptions reach the caller.
      #
      # `color?` comes from Console, which honours both tty and NO_COLOR: paint
      # would otherwise colour the spinner where the rest of the output does not.
      #
      # `stream:` is passed on every call rather than left to whirly's default,
      # which captures `$stdout` once when the gem is loaded: a `$stdout` replaced
      # afterwards would be ignored, and the spinner would draw on the original
      # one while Console writes to the new one.
      # `remove_after_stop` wipes the status line on the way out. Without it the
      # last frame stays on screen — "⠹ fetching notifications" frozen above a
      # summary saying the fetch is done. The status is part of the frame
      # (whirly.rb:220), so the wipe covers the text too, not just the glyph.
      #
      # `append_newline` is turned off with it: it prints a newline after the
      # wipe, which would leave the blank line where the spinner used to be
      # instead of letting the summary take it back.
      def with_spinner(status: 'connecting')
        Whirly.start(spinner: 'dots', color: color?, status: status, stream: $stdout,
                     remove_after_stop: true, append_newline: false)
        yield(->(step) { Whirly.status = "fetching #{step}" })
      ensure
        Whirly.stop
      end
    end
  end
end
