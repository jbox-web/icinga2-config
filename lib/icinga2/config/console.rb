# frozen_string_literal: true

module Icinga2
  module Config
    # Colours, disabled when the output is not a terminal or when NO_COLOR is set,
    # so that a redirected diff stays greppable.
    module Console
      CODES = { bold: 1, red: 31, green: 32, yellow: 33 }.freeze

      def color?
        $stdout.tty? && !ENV.key?('NO_COLOR')
      end

      def paint(text, style)
        color? ? "\e[#{CODES.fetch(style)}m#{text}\e[0m" : text.to_s
      end

      def line(text = '', style: nil)
        $stdout.puts(style ? paint(text, style) : text)
      end
    end
  end
end
