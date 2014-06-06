#!/usr/bin/env ruby

require 'psych'

ENV['MOZREPL_GEM_MODE'] ||= 'development'
ENV['RACK_ENV'] = ENV['MOZREPL_GEM_MODE']

require 'brewed'
Log.open :'>1', :output

require 'mozrepl'

MozRepl.lock_repl do
  mozrepl = MozRepl.new
  actor   = mozrepl.actor

  if false
    actor.nav_page 'http://www.newsobserver.com/'

    puts "\n==Getting HTML=="
    html = actor.get_html '//div[@id="display_rail"]'
    puts Psych.dump(html)
  end

  if false
    actor.nav_page 'http://www.newsobserver.com/'

    puts "\n==Getting Text=="
    text = actor.get_text '//ul[@id="headline_rail"]/li/h3'
    text = text.map { |t| '* ' + t }
    puts text.join("\n")
  end

  if false
    actor.nav_page 'http://www.newsobserver.com/'

    puts "\n==Getting Attrs=="
    attrs = actor.get_attrs '//div[@id="main"]'
    puts Psych.dump(attrs)
  end

  if false
    actor.nav_page 'http://www.newsobserver.com/'

    puts "\nRetrieving page URL..."
    pageurl = actor.get_url
    raise "no page url returned from the REPL" unless pageurl.is_str?

    puts "\nRetrieving element attributes..."
    xpath = '//ul[@id="headline_rail"]/li[position()=1]//a'
    attrs = actor.get_attrs xpath
    attrs = attrs.shift if attrs.is_array?
    raise "no attributes were found" unless attrs.is_hash?
    raise "no URL in attributes" unless attrs[:href].is_str?

    puts "\nClicking on element..."
    clicked = actor.click xpath
    puts "\tclicked: #{clicked.safe_s}"

    puts "\nRetrieving new page URL..."
    newurl = actor.get_url
    puts "\t    href: #{attrs[:href]}"
    puts "\tpage url: #{newurl}"
  end

  if true
    puts "\nNavigating to Bootstrap..."
    actor.nav_page 'http://getbootstrap.com/customize/'

    puts "\nWaiting for form fields..."
    actor.wait_for '//input[@id="input-@brand-danger"]', :raise => true

    form_xpaths =
      %w[
          input-@gray-darker
          input-@gray-dark
          input-@gray
          input-@gray-light
          input-@gray-lighter
          input-@brand-primary
      ].map { |id| %Q|//input[@id="#{id}"]| }

    puts "\nGetting form values..."
    form_values = actor.get_form_fields form_xpaths
    puts Psych.dump(form_values)

    puts "\nSetting form values..."

    set_form_fields =
        form_xpaths.map { |xpath| {:xpath => xpath, :value => xpath} }
    rc = actor.set_form_fields set_form_fields
    puts Psych.dump(rc)
  end

  mozrepl.close

end

puts "\nDONE!"