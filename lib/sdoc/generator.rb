# frozen_string_literal: true

require 'pathname'
require 'fileutils'
require 'json'

require 'sdoc/templatable'
require 'sdoc/helpers'
require 'sdoc/version'
require 'rdoc'

require 'active_support/all'

class RDoc::ClassModule
  def with_documentation?
    document_self_or_methods || classes_and_modules.any?{ |c| c.with_documentation? }
  end
end

class RDoc::Options
  attr_accessor :github
  attr_accessor :search_index
end

class RDoc::Generator::SDoc
  RDoc::RDoc.add_generator self

  DESCRIPTION = 'Searchable HTML documentation'

  include SDoc::Templatable
  include SDoc::Helpers

  GENERATOR_DIRS = [File.join('sdoc', 'generator')]

  SEARCH_INDEX_FILE = File.join 'js', 'search_index.js'

  FILE_DIR = 'files'
  CLASS_DIR = 'classes'

  RESOURCES_DIR = File.join('resources', '.')

  attr_reader :base_dir
  attr_reader :options

  ##
  # The RDoc::Store that is the source of the generated content

  attr_reader :store

  def self.setup_options(options)
    opt = options.option_parser
    opt.separator nil
    opt.separator "SDoc generator options:"

    # FIXME: Use options
    # options.github = true
    opt.separator nil
    opt.on("--github", "-g",
            "Generate links to github.") do |value|
      options.github = true
    end

    opt.separator nil
    opt.on("--version", "-v", "Output current version") do
      puts SDoc::VERSION
      exit
    end
  end

  def initialize(store, options)
    @store   = store
    @options = options
    if @options.respond_to?('diagram=')
      @options.diagram = false
    end
    @options.pipe = true
    @github_url_cache = {}

    @base_dir = Pathname.pwd.expand_path
    @json_index = RDoc::Generator::JsonIndex.new(self, options)
    @template_dir = Pathname.new(options.template_dir)
    @output_dir = Pathname(@options.op_dir).expand_path(@base_dir)
  end

  def generate
    @files = @store.all_files.sort
    @classes = @store.all_classes_and_modules.sort
    @json_index.generate
    @json_index.generate_gzipped

    FileUtils.mkdir_p(@output_dir)
    generate_navigation # original code
    copy_resources
    generate_search_index
    generate_file_files
    generate_class_files
  end

  def class_dir
    CLASS_DIR
  end

  def file_dir
    FILE_DIR
  end

  private

  ### Output progress information if debugging is enabled
  def debug_msg( *msg )
    return unless $DEBUG_RDOC
    $stderr.puts( *msg )
  end

  def generate_class_files
    templatefile = @template_dir + 'class.rhtml'

    @classes.each do |klass|
      debug_msg "  working on %s (%s)" % [ klass.full_name, klass.path ]
      outfile     = @output_dir + klass.path
      rel_prefix  = @output_dir.relative_path_from( outfile.dirname )

      debug_msg "  rendering #{outfile}"
      self.render_template( templatefile, binding(), outfile ) unless @options.dry_run
    end
  end

  ### Generate a documentation file for each file
  def generate_file_files
    debug_msg "Generating file documentation in #@output_dir"
    templatefile = @template_dir + 'file.rhtml'

    @files.each do |file|
      outfile     = @output_dir + file.path
      debug_msg "  working on %s (%s)" % [ file.full_name, outfile ]
      rel_prefix  = @output_dir.relative_path_from( outfile.dirname )

      debug_msg "  rendering #{outfile}"
      self.render_template( templatefile, binding(), outfile ) unless @options.dry_run
    end
  end

  ### Generate file with links for the search engine
  def generate_search_index
    debug_msg "Generating search engine index in #@output_dir"
    templatefile = @template_dir + 'search_index.rhtml'
    outfile      = @output_dir + 'panel/links.html'

    self.render_template( templatefile, binding(), outfile ) unless @options.dry_run
  end

  def generate_navigation
    topclasses = @classes.select { |klass| !(RDoc::ClassModule === klass.parent) }
    tree = generate_file_tree + generate_class_tree_level(topclasses)
    File.write("#{@template_dir}/resources/navigation.html", nav_template.squish!)
  end

  def nav_template
    templatefile = @template_dir + '_navigation_tree.html.erb'
    include_template(templatefile, { tree: menu_tree, nested: false })
  end

  # Recursivly build class tree structure
  def generate_class_tree_level(classes, visited = {})
    tree = []
    classes.select do |klass|
      !visited[klass] && klass.with_documentation?
    end.sort.each do |klass|
      visited[klass] = true
      item = [
        klass.name,
        klass.document_self_or_methods ? klass.path : '',
        klass.module? ? '' : (klass.superclass ? " < #{String === klass.superclass ? klass.superclass : klass.superclass.full_name}" : ''),
        generate_class_tree_level(klass.classes_and_modules, visited)
      ]
      tree << item
    end
    tree
  end

  def menu_tree
    topclasses = @classes.select { |klass| !(RDoc::ClassModule === klass.parent) }
    generate_file_tree + generate_class_tree_level(topclasses)
  end

  ### Determines index path based on @options.main_page (or lack thereof)
  def index_path
    # Break early to avoid a big if block when no main page is specified
    default = @files.first.path
    return default unless @options.main_page

    # Transform class name to file path
    if @options.main_page.include?("::")
      slashed = @options.main_page.sub(/^::/, "").gsub("::", "/")
      "%s/%s.html" % [ class_dir, slashed ]
    elsif file = @files.find { |f| f.full_name == @options.main_page }
      file.path
    else
      default
    end
  end

  ### Copy all the resource files to output dir
  def copy_resources
    resources_path = @template_dir + RESOURCES_DIR
    debug_msg "Copying #{resources_path}/** to #{@output_dir}/**"
    FileUtils.cp_r resources_path.to_s, @output_dir.to_s unless @options.dry_run
  end

  class FilesTree
    attr_reader :children
    def add(path, url)
      path = path.split(File::SEPARATOR) unless Array === path
      @children ||= {}
      if path.length == 1
        @children[path.first] = url
      else
        @children[path.first] ||= FilesTree.new
        @children[path.first].add(path[1, path.length], url)
      end
    end
  end

  def generate_file_tree
    if @files.length > 1
      @files_tree = FilesTree.new
      @files.each do |file|
        @files_tree.add(file.relative_name, file.path)
      end
      [['', '', 'files', generate_file_tree_level(@files_tree)]]
    else
      []
    end
  end

  def generate_file_tree_level(tree)
    tree.children.keys.sort.map do |name|
      child = tree.children[name]
      if String === child
        [name, child, '', []]
      else
        ['', '', name, generate_file_tree_level(child)]
      end
    end
  end
end
