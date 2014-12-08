'' || eval('begin = 0'); _ = nil
=begin
; eval(Opal.compile('=begin\n' + heredoc(function () {/*
=end

require 'native'
require 'native_object_writer'
require 'native_adaptable_class'

module OpalOnAngularities

  def self.angular
    Angular.new(`angular`)
  end

  class Angular < Native::Object

    def module(*args, &block)
      Module.new(super.to_n)
    end

  end

  class Module < Native::Object

    def register_adaptables(*adaptables)
      adaptables.each do |args|
        case args
        when Array
          adaptable = args.shift
        when Hash
          args = args.first
          adaptable = args.shift
        else
          adaptable = args
          args = []
        end
        adaptable.register_to(self, *args)
      end
    end

  end

end


module OpalOnAngularities
  module DependencyInjectedFunction

    # for angular dependency injection
    # yields dependencies as a Hash
    def with_dependencies(*dependencies, &block)
      fn = proc do |*resolved_dependencies|
        dependencies_by_name = Hash[dependencies.zip(resolved_dependencies.map { |o| Native(o) })]
        Native.convert(block.(dependencies_by_name))
      end
      [*dependencies, fn].to_n
    end

    # for angular dependency injection, but like NativeObjectWriter.function
    # yields dependencies as a Hash
    def function_with_dependencies(*dependencies, &block)
      with_dependencies(dependencies) do |dependencies_by_name|
        fn = NativeObjectWriter::Wrapper.new(`this`)
        fn.instance_exec(dependencies_by_name, &block)
        fn
      end
    end

  end
  self.extend(DependencyInjectedFunction)
end


module OpalOnAngularities
  module AngularAdaptable

    DEPENDENCIES = []

    def self.included(klass)
      klass.extend NativeAdaptableClass
      klass.extend DependencyInjectedFunction
      klass.extend ClassMethods
    end

    module ClassMethods

      def delegate_messing_to(target_name = nil, &block)
        target_proc =
          case
          when block_given?
            block
          when %r|^@.*| =~ target_name.to_s
            ->(selff) { selff.instance_variable_get(target_name) }
          when target_name
            target_name.to_sym.to_proc
          else
            raise ArgumentError
          end

        define_method :method_missing do |*args, &block|
          target = target_proc.(self)
          target.__send__(*args, &block)
        end

        define_method :respond_to_missing? do |name, *args|
          target = target_proc.(self)
          target.respond_to?(name, *args)
        end

      end

    end

  end
end


module OpalOnAngularities
  module AngularAdaptable
    module ProvidesConstructor

      def self.included(klass)
        klass.send(:include, AngularAdaptable)
        klass.extend ClassMethods
      end

      module ClassMethods

        def provided
          raise 'abstract'
        end

        def default_name
          self.name
        end

        def register_to(mod, name = self.default_name)
          mod.__send__(provided, name, native_adapter_with_dependencies)
        end

        def native_adapter_with_dependencies
          dependencies = self::DEPENDENCIES
          fn = NativeObjectWriter.function(dependencies: dependencies) do |*resolved_dependencies|
            dependencies_by_name = Hash[pass_ons[:dependencies].zip(resolved_dependencies.map { |o| Native(o) })]
            opal_instance = `#@native.$_opal_class_$`.new(dependencies_by_name)
            `Object.defineProperty(#@native, '$_opal_instance_$', {get: function() { return #{opal_instance}; }})`
            opal_instance
          end
          `#{fn}.prototype = #{self.native_adapter_class}.prototype`
          [*dependencies, fn].to_n
        end

      end

    end
  end
end


module OpalOnAngularities
  module AngularAdaptable
    module ProvidesController

      def self.included(klass)
        klass.send(:include, ProvidesConstructor)
        klass.extend ClassMethods
      end

      module ClassMethods

        def provided
          :controller
        end

      end

    end
  end
end


module OpalOnAngularities
  module AngularAdaptable
    module ProvidesService

      def self.included(klass)
        klass.send(:include, ProvidesConstructor)
        klass.extend ClassMethods
      end

      module ClassMethods

        def provided
          :service
        end

      end

    end
  end
end


module OpalOnAngularities
  module AngularAdaptable
    module ProvidesFactory

      def self.included(klass)
        klass.send(:include, AngularAdaptable)
        klass.extend ClassMethods
      end

      module ClassMethods

        def provided
          :factory
        end

        def default_name
          /(.)(.*)/.match(self.name) do |m|
            m[1].downcase + m[2]
          end
        end

        def register_to(mod, name = self.default_name)
          mod.__send__(provided, name, with_dependencies(*self::DEPENDENCIES) { |deps| self.call(deps) })
        end

        def call(deps)
          raise 'abstract'
        end

      end

    end
  end
end


module OpalOnAngularities
  module AngularAdaptable
    module ProvidesClassAsFactory

      def self.included(klass)
        klass.send(:include, ProvidesFactory)
        klass.extend ClassMethods
      end

      module ClassMethods

        def provided
          :factory
        end

        def default_name
          self.name
        end

        def call(deps)
          self.resolved_dependencies = deps
          self.native_adapter_class
        end

        attr_accessor :resolved_dependencies

      end

      def resolved_dependencies(*args)
        case args.length
        when 0
          self.class.resolved_dependencies
        when 1
          self.class.resolved_dependencies[args.first]
        else
          raise ArgumentError, "wrong number of arguments (#{args.length} for 0 or 1)"
        end
      end

    end
  end
end


module OpalOnAngularities
  module AngularAdaptable
    module ProvidesFilter

      def self.included(klass)
        klass.send(:include, ProvidesFactory)
        klass.extend ClassMethods
      end

      module ClassMethods

        def default_name
          /(.)(.*)Filter/.match(self.name) do |m|
            m[1].downcase + m[2]
          end
        end

        def provided
          :filter
        end

        def call(deps)
          self.new(deps).method(:filter).to_proc
        end

      end

      def initialize(deps)
      end

      def filter(input)
        raise 'abstract'
      end

    end
  end
end


module OpalOnAngularities
  module AngularAdaptable
    module ProvidesDirective

      def self.included(klass)
        klass.send(:include, ProvidesFactory)
        klass.extend ClassMethods
      end

      module ClassMethods

        def default_name
          /(.)(.*)Directive/.match(self.name) do |m|
            m[1].downcase + m[2]
          end
        end

        def provided
          :directive
        end

        def define_directive(&block)
          @directive_definition = block
        end

        attr_reader :directive_definition

        def call(deps)
          NativeObjectWriter.new_object(self.new, deps, &directive_definition)
        end

      end

      def initialize(deps)
      end

    end
  end
end


Angular = OpalOnAngularities.angular
AngularAdaptable = OpalOnAngularities::AngularAdaptable

#*/})));
