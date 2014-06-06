#!/usr/bin/env ruby

require 'psych'

ENV['MOZREPL_GEM_MODE'] ||= 'development'
ENV['RACK_ENV'] = ENV['MOZREPL_GEM_MODE']

require 'brewed'
Log.open :'>1', :output

require 'mozrepl'

URLS =
    %w[
        http://www.newsobserver.com/
        http://getbootstrap.com/customize/
        http://www.tvrage.com/mytvrage.php?page=myschedule
      ].freeze

MozRepl.lock_repl do
  mozrepl = MozRepl.new
  actor   = mozrepl.actor

  puts "\nCreating tabs and navigating to URLs..."
  URLS.each do |url|
    puts "\n\t#{url}"
    tabs = actor.add_tab
    puts Psych.dump(tabs)

    actor.nav_page url

    sleep 0.5
  end

  puts "\nActivating tabs..."
  [0, 2, 1].each do |tabidx|
    puts "\n\tactivating #{URLS[tabidx]}"
    rc = actor.activate_tab URLS[tabidx]
    sleep 2
  end

  mozrepl.close
end

puts "\nDONE!"
