require 'test_helper'

class TestFileSystem
  def read_template_file(template_path, context)
    case template_path
    when "product"
      "Product: {{ product.title }} "

    when "locale_variables"
      "Locale: {{echo1}} {{echo2}}"

    when "variant"
      "Variant: {{ variant.title }}"

    when "nested_template"
      "{% include 'header' %} {% include 'body' %} {% include 'footer' %}"

    when "body"
      "body {% include 'body_detail' %}"

    when "nested_product_template"
      "Product: {{ nested_product_template.title }} {%include 'details'%} "

    when "recursively_nested_template"
      "-{% include 'recursively_nested_template' %}"

    when "pick_a_source"
      "from TestFileSystem"

    else
      template_path
    end
  end
end

class OtherFileSystem
  def read_template_file(template_path, context)
    'from OtherFileSystem'
  end
end

class CountingFileSystem
  attr_reader :count
  def read_template_file(template_path, context)
    @count ||= 0
    @count += 1
    'from CountingFileSystem'
  end
end

class CustomInclude < Liquid::Tag
  Syntax = /(#{Liquid::QuotedFragment}+)(\s+(?:with|for)\s+(#{Liquid::QuotedFragment}+))?/o

  def initialize(tag_name, markup, tokens)
    markup =~ Syntax
    @template_name = $1
    super
  end

  def parse(tokens)
  end

  def blank?
    false
  end

  def render(context)
    @template_name[1..-2]
  end
end

class IncludeTagTest < Test::Unit::TestCase
  include Liquid

  def setup
    Liquid::Template.file_system = TestFileSystem.new
  end

  def test_include_tag_looks_for_file_system_in_registers_first
    assert_equal 'from OtherFileSystem',
      Template.parse("{% include 'pick_a_source' %}").render!({}, :registers => {:file_system => OtherFileSystem.new})
  end


  def test_include_tag_with
    assert_template_result "Product: Draft 151cm ",
      "{% include 'product' with products[0] %}", "products" => [ {'title' => 'Draft 151cm'}, {'title' => 'Element 155cm'} ]
  end

  def test_include_tag_with_default_name
    assert_template_result "Product: Draft 151cm ",
      "{% include 'product' %}", "product" => {'title' => 'Draft 151cm'}
  end

  def test_include_tag_for
    assert_template_result "Product: Draft 151cm Product: Element 155cm ",
      "{% include 'product' for products %}", "products" => [ {'title' => 'Draft 151cm'}, {'title' => 'Element 155cm'} ]
  end

  def test_include_tag_with_local_variables
    assert_template_result "Locale: test123 ", "{% include 'locale_variables' echo1: 'test123' %}"
  end

  def test_include_tag_with_multiple_local_variables
    assert_template_result "Locale: test123 test321",
      "{% include 'locale_variables' echo1: 'test123', echo2: 'test321' %}"
  end

  def test_include_tag_with_multiple_local_variables_from_context
    assert_template_result "Locale: test123 test321",
      "{% include 'locale_variables' echo1: echo1, echo2: more_echos.echo2 %}",
      'echo1' => 'test123', 'more_echos' => { "echo2" => 'test321'}
  end

  def test_nested_include_tag
    assert_template_result "body body_detail", "{% include 'body' %}"

    assert_template_result "header body body_detail footer", "{% include 'nested_template' %}"
  end

  def test_nested_include_with_variable
    assert_template_result "Product: Draft 151cm details ",
      "{% include 'nested_product_template' with product %}", "product" => {"title" => 'Draft 151cm'}

    assert_template_result "Product: Draft 151cm details Product: Element 155cm details ",
      "{% include 'nested_product_template' for products %}", "products" => [{"title" => 'Draft 151cm'}, {"title" => 'Element 155cm'}]
  end

  def test_recursively_included_template_does_not_produce_endless_loop

    infinite_file_system = Class.new do
      def read_template_file(template_path, context)
        "-{% include 'loop' %}"
      end
    end

    Liquid::Template.file_system = infinite_file_system.new

    assert_raise(Liquid::StackLevelError) do
      Template.parse("{% include 'loop' %}").render!
    end

  end

  def test_backwards_compatability_support_for_overridden_read_template_file
    infinite_file_system = Class.new do
      def read_template_file(template_path) # testing only one argument here.
        "- hi mom"
      end
    end

    Liquid::Template.file_system = infinite_file_system.new

    Template.parse("{% include 'hi_mom' %}").render!
  end

  def test_dynamically_choosen_template
    assert_template_result "Test123", "{% include template %}", "template" => 'Test123'
    assert_template_result "Test321", "{% include template %}", "template" => 'Test321'

    assert_template_result "Product: Draft 151cm ", "{% include template for product %}",
      "template" => 'product', 'product' => { 'title' => 'Draft 151cm'}
  end

  def test_include_tag_caches_second_read_of_same_partial
    file_system = CountingFileSystem.new
    assert_equal 'from CountingFileSystemfrom CountingFileSystem',
      Template.parse("{% include 'pick_a_source' %}{% include 'pick_a_source' %}").render!({}, :registers => {:file_system => file_system})
    assert_equal 1, file_system.count
  end

  def test_include_tag_doesnt_cache_partials_across_renders
    file_system = CountingFileSystem.new
    assert_equal 'from CountingFileSystem',
      Template.parse("{% include 'pick_a_source' %}").render!({}, :registers => {:file_system => file_system})
    assert_equal 1, file_system.count

    assert_equal 'from CountingFileSystem',
      Template.parse("{% include 'pick_a_source' %}").render!({}, :registers => {:file_system => file_system})
    assert_equal 2, file_system.count
  end

  def test_include_tag_within_if_statement
    assert_template_result "foo_if_true", "{% if true %}{% include 'foo_if_true' %}{% endif %}"
  end

  def test_custom_include_tag
    original_tag = Liquid::Template.tags['include']
    Liquid::Template.tags['include'] = CustomInclude
    begin
      assert_equal "custom_foo",
        Template.parse("{% include 'custom_foo' %}").render!
    ensure
      Liquid::Template.tags['include'] = original_tag
    end
  end

  def test_custom_include_tag_within_if_statement
    original_tag = Liquid::Template.tags['include']
    Liquid::Template.tags['include'] = CustomInclude
    begin
      assert_equal "custom_foo_if_true",
        Template.parse("{% if true %}{% include 'custom_foo_if_true' %}{% endif %}").render!
    ensure
      Liquid::Template.tags['include'] = original_tag
    end
  end

  def test_does_not_add_error_in_strict_mode_for_missing_variable
    Liquid::Template.file_system = TestFileSystem.new

    a = Liquid::Template.parse(' {% include "nested_template" %}')
    a.render!
    assert_empty a.errors
  end
end # IncludeTagTest
