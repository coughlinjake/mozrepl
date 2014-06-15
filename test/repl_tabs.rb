#!/usr/bin/env ruby

require 'psych'

ENV['MOZREPL_MODE'] ||= 'development'
ENV['RACK_ENV'] = ENV['MOZREPL_MODE']

require 'brewed'
Log.open :id    => :mozrepl,
         :fname => '__mozrepl.rlog',
         :level => :debug

require 'mozrepl'

URLS =
    [
        [ 'http://www.newsobserver.com/',                       'newsobserver.com' ],
        [ 'http://getbootstrap.com/customize/',                 'getbootstrap' ],
        [ 'http://www.tvrage.com/mytvrage.php?page=myschedule', 'mytvrage' ]
    ].freeze

MozRepl.lock_repl do
  mozrepl = MozRepl.new
  actor   = mozrepl.actor

  puts "\nCreating tabs and navigating to URLs..."
  URLS.each do |(url, tabpat)|
    puts "\n\t#{url}"
    tabs = actor.add_tab
    puts Psych.dump(tabs)

    actor.nav_page url

    sleep 0.5
  end

  puts "\nActivating tabs..."
  [0, 2, 1].each do |tabidx|
    puts "\n\tactivating #{URLS[tabidx][1]}"
    rc = actor.activate_tab URLS[tabidx][1]
    sleep 2
  end

  mozrepl.close
end

puts "\nDONE!"
