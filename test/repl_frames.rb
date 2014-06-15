#!/usr/bin/env ruby

require 'psych'

ENV['MOZREPL_MODE'] ||= 'development'
ENV['RACK_ENV'] = ENV['MOZREPL_MODE']

URL = 'http://localhost:9000/'.freeze

FRAMES = [
    {
        :name => 'bottom',
        :frame_url => "bottom.html",
        :xpath => '//h1[@id="bottom"]',
    },
    {
        :name => 'menu',
        :frame_url => "sidebar.html",
        :xpath => '//a[@id="parent-folder"]',
    },
    {
        :name => 'main',
        :frame_url => "main.html",
        :xpath => '//h2[@id="main_frame"]',
    },
].freeze

#FRAMES = [
#    {
#        :name => 'bottom',
#        :frame_url => "http://127.0.0.1:9000/frames/bottom.html",
#        :xpath => '//h1[@id="bottom"]',
#    },
#    {
#        :name => 'menu',
#        :frame_url => "http://127.0.0.1:9000/frames/sidebar.html",
#        :xpath => '//a[id="blocks-classes"]',
#    },
#    {
#        :name => 'main',
#        :frame_url => "http://127.0.0.1:9000/frames/main.html",
#        :xpath => '//a[@id="parent-folder"]',
#    },
#].freeze

require 'brewed'
Log.open :id    => :mozrepl,
         :fname => '__mozrepl.rlog',
         :level => :debug

require 'mozrepl'

puts "\n==WARNING==\n"
puts "DON'T FORGET TO START THE SERVER WITH ./__darkhttp.sh!!"

MozRepl.lock_repl do
  mozrepl = MozRepl.new
  fractor = mozrepl.frames_actor

  puts "\nNavigating to '#{URL}'..."
  fractor.nav_page URL

  puts "\nProcessing frames..."
  FRAMES.each do |frame|
    puts "\n\nFRAME #{frame[:name]}..."
    fractor.switch_to frame[:frame_url]

    puts "\n\tGetting HTML..."
    html = fractor.get_html frame[:xpath]
    puts "\t#{Psych.dump(html)}"

    puts "\n\tGetting Log..."
    fractor.get_repl_log

    puts "\n"
  end

end

puts "\nDONE!"
