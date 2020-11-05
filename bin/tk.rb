#!/usr/bin/env ruby
#
#

require 'tk'

#puts Tk.chooseDirectory(
#	:initialdir=>'/var/tmp/mozilla',
#	:title=>'Firefox mozilla print 2 file'
#)

dest="foo.pdf"
Tk::messageBox( :type => "ok",
			   :message => "Destination file defaulting to #{dest}",
			   :icon => "warning",
			   :title => "Firefox print to file" )

puts Tk.getSaveFile(
	:initialdir=>'/var/tmp/mozilla',
	:initialfile=>'mozilla.pdf',
	:title=>'Firefox mozilla print 2 file',
	:confirmoverwrite=>false,
	:defaultextension=>'.pdf',
	:filetypes=>[
		['PDF Files', '.pdf'],
		['ALL Files', '*']
	]
	#,:filetypes=>[ { "PDF Files" => "pdf" } ]
)

exit

#puts Tk::messageBox :type => 'ok',
#	    :message => 'this is an info message',
#	    :icon => 'info', :title => 'Firefox info'

root = TkRoot.new {title "Feet to Meters"}

content = Tk::Tile::Frame.new(root) {padding "3 3 12 12"}.grid( :sticky => 'nsew')
TkGrid.columnconfigure root, 0, :weight => 1; TkGrid.rowconfigure root, 0, :weight => 1

$feet = TkVariable.new
$meters = TkVariable.new

f = Tk::Tile::Entry.new(content) {width 7; textvariable $feet}.grid( :column => 2, :row => 1, :sticky => 'we' )
Tk::Tile::Label.new(content) {textvariable $meters}.grid( :column => 2, :row => 2, :sticky => 'we');
Tk::Tile::Button.new(content) {text 'Calculate'; command {calculate}}.grid( :column => 3, :row => 3, :sticky => 'w')

Tk::Tile::Label.new(content) {text 'feet'}.grid( :column => 3, :row => 1, :sticky => 'w')
Tk::Tile::Label.new(content) {text 'is equivalent to'}.grid( :column => 1, :row => 2, :sticky => 'e')
Tk::Tile::Label.new(content) {text 'meters'}.grid( :column => 3, :row => 2, :sticky => 'w')

TkWinfo.children(content).each {|w| TkGrid.configure w, :padx => 5, :pady => 5}
f.focus
root.bind("Return") {calculate}

def calculate
  begin
     $meters.value = (0.3048*$feet*10000.0).round()/10000.0
  rescue
     $meters.value = ''
  end
end

Tk.mainloop
