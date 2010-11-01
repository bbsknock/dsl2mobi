$KCODE='u'

require 'erb'
require 'fileutils'
require 'optparse'
require 'set'

require 'lib/transliteration'
require 'lib/norm_tags'
require 'lib/templates'

FORMS = {}
CARDS = {}
HWDS = Set.new
cards_list = []

$VERSION = '0.1'
$FAST = false
$FORCE = false
$NORMALIZE_TAGS = true
$count = 0
$WORD_FORMS_FILE = nil
$DSL_FILE = nil
$HTML_ONLY = false
$OUT_DIR = "."
$IN = nil

opts = OptionParser.new
# opts.banner = "Usage: dsl2mobi [options]"

opts.on("-i", "--in DSL_FILE", "convert this DSL file") { |val|
  $DSL_FILE = val
  $stderr.puts "Reading DSL: #{$DSL_FILE}"
}

opts.on("-o", "--out DIR", "convert to directory") { |val|
  $OUT_DIR = val
  $stderr.puts "INFO: Output directory: #{$OUT_DIR}"
  if File.file?($OUT_DIR)
    $stderr.puts "ERROR: Target directory is a file."
    exit
  end
  unless File.exist?($OUT_DIR)
    $stderr.puts "INFO: Output directory doesn't exist, creating..."
    Dir.mkdir($OUT_DIR)
  end
}

opts.on("-w FILE", "--wordforms FILE", "use the word forms from this file") { |val|
  $WORD_FORMS_FILE = val
  $stderr.puts "Using word forms file: #{$WORD_FORMS_FILE}"
}

opts.separator ""
opts.separator "Advanced options:"

opts.on("-n true/false", "--normtags true/false", "normalize DSL tags (default: true)") { |val|
  $NORMALIZE_TAGS = !!(val =~ /(true|1|on)/i)
  $stderr.puts "DSL tags normalization: #{$NORMALIZE_TAGS}"
}

opts.on("-t", "--htmlonly true/false", "produce HTML only (default: false)") { |val|
  $HTML_ONLY = !!(val =~ /(true|1|on)/i)
  $stderr.puts "Generate HTML only: #{$HTML_ONLY}"
}

opts.on("-f", "--force", "overwrite existing files") { |val|
  $FORCE = true
}

opts.on("-s", "--sample", "generate small sample") { |val|
  $FAST = true
}

opts.separator ""
opts.separator "Common options:"

opts.on("-v", "--version", "print version") {
  puts "Dsl2Mobi Converter, ver. #{$VERSION}"
  puts "Copyright (C) 2010 VVSiz"
  exit
}

opts.on("-h", "--help", "print help") {
  puts opts.to_s
  exit
}

opts.separator ""
opts.separator "Example: ruby dsl2mobi -i in.dsl -o result_dir -t forms_EN.txt"
opts.separator "Convert in.dsl file into result_dir directory, with English wordforms"


# my_argv = [ "-w", "WORD_FORMS.txt", "-n", "false", "-i", "in.dsl", "--htmlonly", "true", "-o", "test", "-v", "-h" ]

rest = opts.parse(*ARGV)
$stderr.puts "WARNING: Some options are not recognized: \"#{rest.join(', ')}\"" unless (rest.empty?)

unless $DSL_FILE
  $stderr.puts "ERROR: Input DSL file is not specified"
  $stderr.puts
  $stderr.puts opts.to_s
  exit
end

$stderr.puts "INFO: DSL Tags normalization: #{$NORMALIZE_TAGS}"

# puts opts.to_s
# exit

class Card
  #attr_reader :hwd, :body
  def initialize(hwd)
    @hwd, @body, @empty = hwd, [], []
    if @hwd =~ /;\s/
      @sub_hwds = hwd.split(/\s*;\s*/)
    else
      @sub_hwds = []
    end
    if @hwd =~ /\{\\\(/
      $stderr.puts "ERROR: Can't handle headwords with brackets: #{@hwd}"
      exit
    end
  end

  def print_out(io)
    if (@body.empty?)
      $stderr.puts "ERROR: Original file contains multiple headwords fro the same card: #{@hwd}"
      $stderr.puts "Make sure that the only one headword for each card"
      exit
    end

    # handle headword
    # puts break_headword

    hwd = clean_hwd(@hwd)
    io.puts %Q{<a name="\##{href_hwd(@hwd)}"/>}
    io.puts '<idx:entry name="word" scriptable="yes">'
    io.puts %Q{<div><font  size="6" color="#002984"><b><idx:orth>}
    io.puts clean_hwd_to_display(@hwd)

    # inflections
    if hwd !~ /[-\.'\s]/
      if (FORMS[hwd]) # got some inflections
        forms = FORMS[hwd].flatten.uniq

        # delete forms that explicitly exist in the dictionary
        forms = forms.delete_if {|form| HWDS.include?(form)}

        if (forms.size > 0)
          io.puts "<idx:infl>"
          forms.each { |form| io.puts %Q{    <idx:iform value="#{form}"/>} }
          io.puts "</idx:infl>"
        end

        # $stderr.puts "HWD: #{hwd} -- #{FORMS[hwd].flatten.uniq.join(', ')}"
      end
    end

    io.puts "</idx:orth></b></font></div>"

    trans = transliterate(hwd)
    if (trans != hwd)
      io.puts %Q{<idx:orth value="#{trans.gsub(/"/, '')}"/>}
    end

    # &nbsp; below is intentional, to avoid Kindle's bug
    # puts "<h2>&nbsp;<b><idx:orth>#{@hwd}</idx:orth></b></h2>"
    # puts @hwd

    # handle body
    @body.each { |line|
      indent = 0
      m = line.match(/^\[m(\d+)\]/)
      indent = m[1] if m

      # \[ --> _{_
      line.gsub!('\[', '_{_')
      line.gsub!('\]', '_}_')

      # (\#16) --> (#16). in ASIS.
      line.gsub!('\\#', '#')

      # remove trn tags
      line.gsub!(/\[\/?!?tr[ns]\]/, '')

      # remove lang tags
      line.gsub!(/\[\/?lang[^\]]*\]/, '')

      # remove com tags
      line.gsub!(/\[\/?com\]/, '')

      # remove s tags
      line.gsub!(/\[s\](.*?)\[\/s\]/) do |match|
        file_name = $1

        # handle images
        if file_name =~ /.(jpg|jpeg|bmp|gif)$/
          # hspace="0" align="absbottom" hisrc=
          # %Q{<img hspace="0" vspace="0" align="middle" src="#{$1}"/>}
          %Q{<img hspace="0" hisrc="#{file_name}"/>}
        elsif file_name =~ /.wav$/
          # just ignore it
        else
          $stderr.puts "WARN: Don't know how to handle media file: #{file_name}"
        end
      end

      # remove t tags
      line.gsub!(/\[t\]/, '<!-- T1 -->')
      line.gsub!(/\[\/?t\]/, '<!-- T2 -->')

      # remove m tags
      line.gsub!(/\[\/?m\d*\]/, '')

      # remove * tags
      line.gsub!('[*]', '')
      line.gsub!('[/*]', '')

      if ($NORMALIZE_TAGS)
        line = Normalizer::norm_tags(line)
      end

      # replace ['] by <u>
      line.gsub!("[']", '<u>')
      line.gsub!("[/']", '</u>')

      # bold
      line.gsub!('[b]', '<b>')
      line.gsub!('[/b]', '</b>')

      # italic
      line.gsub!('[i]', '<i>')
      line.gsub!('[/i]', '</i>')

      # underline
      line.gsub!('[u]', '<u>')
      line.gsub!('[/u]', '</u>')

      line.gsub!('[sup]', '<sup>')
      line.gsub!('[/sup]', '</sup>')

      line.gsub!('[sub]', '<sub>')
      line.gsub!('[/sub]', '</sub>')

      line.gsub!('[ex]', '<span class="dsl_ex">')
      line.gsub!('[/ex]', '</span>')

      # line.gsub!('[ex]', '<ul><ul><li><span class="dsl_ex">')
      # line.gsub!('[/ex]', '</span></li></ul></ul>')

      line.gsub!('[p]', '<span class="dsl_p">')
      line.gsub!('[/p]', '</span>')

      # color translation
      line.gsub!('[c tomato]', '[c   red]')
      line.gsub!('[c slategray]', '[c gray]')

      # ASIS:
      line.gsub!(/\[c   red\](.*?)\[\/c\]/, '[c red]<b>\1</b>[/c]')

      # color
      line.gsub!('[c]', '<font color="green">')
      line.gsub!('[/c]', '</font>')
      line.gsub!(/\[c\s+(\w+)\]/) do |match|
        %Q{<font color="#{$1}">}
      end
      # m = line.match(/^\[c (\w+)\]/)
      # color = m[1] if m

      # _{_ --> [
      line.gsub!('_{_', '[')
      line.gsub!('_}_', ']')

      # remove ref tags
      #line.gsub!(/\[ref\](.*?)\[\/ref\]/, %Q{↑ <a href="\##{href_hwd($1)}">})
      line.gsub!(/(?:↑\s*)?\[ref\](.*?)\[\/ref\]/) do |match|
        %Q{↑ <a href="\##{href_hwd($1)}">#{$1}</a>}
      end
      #line.gsub!('[/ref]', '</a>')

      io.puts %Q{<div class="dsl_m#{indent}">#{line}</div>}
    }

    # handle end of card
    io.puts "</idx:entry>"
    io.puts %Q{<div>\n  <img hspace="0" vspace="0" align="middle" src="padding.gif"/>}
    io.puts %Q{  <table width="100%" bgcolor="#992211"><tr><th widht="100%" height="2px"></th></tr></table>\n</div>}
  end
  def break_headword
    res = "#{@hwd}\n"
    @sub_hwds.each { |sub_hwd|
      res << "#{sub_hwd} {\\(#{@hwd}\\)}\n"
    }
    res
  end
  def detect_duplicates
    @sub_hwds.each { |sub_hwd|
      if (card = CARDS[sub_hwd]) # hwd exists already
        # CUSTOMIZE HERE:
        card << "��������"
        card << "[m1]See ^<<#{@hwd}>>[/m]\n"
        # END OF CUSTOMIZE
        @sub_hwds.delete(sub_hwd)
      end
    }
  end
  def << line
    l = line.strip
    if (l.empty?)
      @empty << line
    else
      @body << line.strip
    end
  end
end

def clean_hwd_global(hwd)
  hwd.gsub('\{', '_<_').gsub('\}', '_>_').
      gsub(/\{.*?\}/, '').
      gsub('_<_', '\{').gsub('_>_', '\}')
end

def clean_hwd_to_display(hwd)
  clean_hwd_global(
    hwd.gsub(/\{\['\]\}(.*?)\{\[\/'\]\}/, '<u>\1</u>') # {[']}txt{[/']} ---> <u>txt</u>
  )
end

def clean_hwd(hwd)
  clean_hwd_global(hwd)
end

def href_hwd(hwd)
  # $stderr.puts "HWD: #{hwd.inspect}"
  # return "" if hwd.nil?
  # .gsub(/<[\w\/]*?>/, '').
  clean_hwd_global(hwd).gsub(/[\s\(\)'"#°!?]+/, '_')
end

def transliterate(hwd)
  Russian::Transliteration.transliterate(hwd)
end

if ($WORD_FORMS_FILE)
  forms_size = 0
  File.open($WORD_FORMS_FILE) do |f|
    f.each do |l|
      l.strip!
      stem, forms = l.split(':')
      stem.strip!
      forms.strip!

      unless FORMS[stem]
        forms_size += 1
        FORMS[stem] = []
      end

      FORMS[stem] << forms.split(/\s*,\s*/)
    end
  end
  $stderr.puts "FORMS SIZE: #{forms_size} -- #{FORMS.size}"
else
  $stderr.puts "INFO: Word forms are not enabled (use --wordforms switch to enable)"
end

# get the full list of headwords in the DSL file
first = true
File.open($DSL_FILE) do |f|
  while (line = f.gets)         # read every line
    if (first)
      # strip UTF-8 BOM, if it's there
      if line[0, 3] == "\xEF\xBB\xBF"
        line = line[3, line.size - 3]
      end
      first = false
    end
    if line =~ /^#/           # ignore comments
      next
    end
    if (line =~ /^[^\t\s]/)   # is headword?
      hwd = clean_hwd(line.strip)        # strip \n\r from the end
      HWDS << hwd
    end
  end
end

def get_base_name
  $DSL_FILE.gsub(/(\..*)*\.dsl$/i, '')
end

$stderr.puts "INFO: Generating only a small sample..." if $FAST

# Calculate where to save the HTML file:
out_file = File.join($OUT_DIR, get_base_name + '.html')
if File.exist?(out_file)
  $stderr.print "WARNING: Output file already exists: \"#{out_file}\". "
  if $FORCE
    $stderr.puts "OVERWRITING!"
  else
    $stderr.puts "Use --force to overwrite."
    exit
  end
end

card = nil
first = true
File.open($DSL_FILE) do |f|

  $stderr.puts "Generating HTML: #{out_file}"
  File.open(out_file, "w+") do |out|

    # print HTML header first
    # TODO: get the info from the DSL file
    title = "NBARS (En-Ru)"
    subtitle = "New Big English-Russian Dictionary"
    html_header = ERB.new(HTML_HEADER_TEMPLATE, 0, "%<>")
    out.puts html_header.result(binding)

    while (line = f.gets)         # read every line
      if (first)
        # strip UTF-8 BOM, if it's there
        if line[0, 3] == "\xEF\xBB\xBF"
          line = line[3, line.size - 3]
        end
        first = false
      end
      if line =~ /^#/           # ignore comments
        # puts line
        next
      end
      if (line =~ /^[^\t\s]/)   # is headword?
        hwd = line.strip        # strip \n\r from the end
        if (CARDS[hwd])
          $stderr.puts "ERROR: Original file contains diplicates: #{hwd}"
          exit
        end
        card.print_out(out) if card
        $count += 1
        break if ($count == 1000 && $FAST)
        card = Card.new(hwd)
        #CARDS[hwd] = card
        #cards_list << card
      else
        card << line if card
      end
    end

    # don't forget the very latest card!
    card.print_out(out) if card

    # end of HTML
    out.puts "</body>"
    out.puts "</html>"
  end
end

# copy CSS and image files
FileUtils::cp(File.expand_path('../lib/dic.css', __FILE__), $OUT_DIR, :verbose => false )
FileUtils::cp(File.expand_path('../lib/padding.gif', __FILE__), $OUT_DIR, :verbose => false )

# generate OPF file
opf_file = File.join($OUT_DIR, get_base_name + '.opf')
if File.exist?(opf_file)
  $stderr.print "WARNING: Output file already exists: \"#{opf_file}\". "
  if $FORCE
    $stderr.puts "OVERWRITING!"
  else
    $stderr.puts "Use --force to overwrite."
    exit
  end
end

$stderr.puts "Generating OPF: #{opf_file}"
File.open(opf_file, "w+") do |out|
  title = "NBARS (En-Ru)"
  language = "en"
  description = ""
  in_lang = "en-us"
  out_lang = "ru"
  html_file = File.basename(out_file)
  opf_content = ERB.new(OPF_TEMPLATE, 0, "%<>")
  out.puts opf_content.result(binding)
end