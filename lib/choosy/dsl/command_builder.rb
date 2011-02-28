require 'choosy/errors'
require 'choosy/converter'
require 'choosy/dsl/option_builder'
require 'choosy/printing/help_printer'
require 'choosy/printing/erb_printer'

module Choosy::DSL
  class CommandBuilder
    HELP = :__help__
    VERSION = :__version__

    attr_reader :command

    def initialize(command)
      @command = command
    end

    def executor(exec=nil, &block)
      if exec.nil? 
        if block_given?
          @command.executor = block
        else
          raise Choosy::ConfigurationError.new("The executor was nil")
        end
      else
        if !exec.respond_to?(:execute!)
          raise Choosy::ConfigurationError.new("Execution class doesn't implement 'execute!'")
        end
        @command.executor = exec
      end
    end

    def summary(msg)
      @command.summary = msg
    end

    def printer(kind, options=nil)
      return if kind.nil?

      p = nil
      if kind == :standard
        p = Choosy::Printing::HelpPrinter.new
      elsif kind == :erb
        p = Choosy::Printing::ERBPrinter.new
        if options.nil? || options[:template].nil?
          raise Choosy::ConfigurationError.new("no template file given to ERBPrinter")
        elsif !File.exist?(options[:template])
          raise Choosy::ConfigurationError.new("the template file doesn't exist: #{options[:template]}")
        end
        p.template = options[:template]
      elsif kind.respond_to?(:print!)
        p = kind
      else
        raise Choosy::ConfigurationError.new("Unknown printing method for help: #{kind}")
      end

      if p.respond_to?(:color) && options && options.has_key?(:color)
        p.color.disable! if !options[:color]
      end

      @command.printer = p
    end
    
    def desc(msg)
      @command.description = msg
    end

    def separator(msg=nil)
      @command.listing << (msg.nil? ? "" : msg)
    end

    def option(arg)
      raise Choosy::ConfigurationError.new("The option name was nil") if arg.nil?
      
      builder = nil

      if arg.is_a?(Hash)
        raise Choosy::ConfigurationError.new("Malformed option hash") if arg.count != 1
        name = arg.keys[0]
        builder = OptionBuilder.new(name)

        to_process = arg[name]
        if to_process.is_a?(Array)
          builder.dependencies to_process
        elsif to_process.is_a?(Hash)
          builder.from_hash to_process
        else
          raise Choosy::ConfigurationError.new("Unable to process option hash")
        end
      else
        builder = OptionBuilder.new(arg)
        raise Choosy::ConfigurationError.new("No configuration block was given") if !block_given?
      end

      yield builder if block_given?
      finalize_builder builder
    end

    # Option types
    def self.create_conversions
      Choosy::Converter::CONVERSIONS.keys.each do |method|
        next if method == :boolean || method == :bool

        define_method method do |sym, desc, config=nil, &block|
          simple_option(sym, desc, true, :one, method, config, &block)
        end

        plural = "#{method}s".to_sym
        define_method plural do |sym, desc, config=nil, &block|
          simple_option(sym, desc, true, :many, method, config, &block)
        end

        underscore = "#{method}_"
        define_method underscore do |sym, desc, config=nil, &block|
          simple_option(sym, desc, false, :one, method, config, &block)
        end

        plural_underscore = "#{plural}_".to_sym
        define_method plural_underscore do |sym, desc, config=nil, &block|
          simple_option(sym, desc, false, :many, method, config, &block)
        end
      end
    end

    create_conversions
    alias :single :string
    alias :single_ :string_

    alias :multiple :strings
    alias :multiple_ :strings_

    def boolean(sym, desc, config=nil, &block)
      simple_option(sym, desc, true, :zero, :boolean, config, &block)
    end
    def boolean_(sym, desc, config=nil, &block)
      simple_option(sym, desc, false, :zero, :boolean, config, &block)
    end
    alias :bool :boolean
    alias :bool_ :boolean_

    def help(msg=nil)
      h = OptionBuilder.new(HELP)
      h.short '-h'
      h.long '--help'
      msg ||= "Show this help message"
      h.desc msg

      h.validate do
        raise Choosy::HelpCalled.new
      end 

      finalize_builder h
    end

    def version(msg)
      v = OptionBuilder.new(VERSION)
      v.long '--version'
      v.desc "The version number"

      v.validate do
        raise Choosy::VersionCalled.new(msg)
      end

      yield v if block_given?
      finalize_builder v
    end

    def arguments(&block)
      raise Choosy::ConfigurationError.new("No block to arguments call") if !block_given?

      command.argument_validation = block
    end
    
    def finalize!
      if @command.printer.nil?
        printer :standard
      end
    end

    private
    def finalize_builder(builder)
      builder.finalize!
      command.builders[builder.option.name] = builder
      command.listing << builder.option

      builder.option
    end

    def format_param(name, count)
      case count
      when :zero then nil
      when :one then name.upcase
      when :many then "#{name.upcase}+"
      end
    end

    def simple_option(sym, desc, allow_short, param, cast, config, &block)
      name = sym.to_s
      builder = OptionBuilder.new sym
      builder.desc desc
      builder.short "-#{name[0]}" if allow_short
      builder.long "--#{name.downcase.gsub(/_/, '-')}"
      builder.param format_param(name, param)
      builder.cast cast
      builder.from_hash config if config

      yield builder if block_given?
      finalize_builder builder
    end
  end
end
