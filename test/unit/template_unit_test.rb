require 'test_helper'

class TemplateUnitTest < Test::Unit::TestCase
  include Liquid

  def test_sets_default_localization_in_document
    t = Template.new
    t.parse('')
    assert_instance_of I18n, t.root.options[:locale]
  end

  def test_sets_default_localization_in_context_with_quick_initialization
    t = Template.new
    t.parse('{{foo}}', :locale => I18n.new(fixture("en_locale.yml")))

    assert_instance_of I18n, t.root.options[:locale]
    assert_equal fixture("en_locale.yml"), t.root.options[:locale].path
  end

  def test_with_cache_classes_tags_returns_the_same_class
    original_cache_setting = Liquid.cache_classes
    Liquid.cache_classes = true

    original_klass = Class.new
    Object.send(:const_set, :CustomTag, original_klass)
    Template.register_tag('custom', CustomTag)

    Object.send(:remove_const, :CustomTag)

    new_klass = Class.new
    Object.send(:const_set, :CustomTag, new_klass)

    assert Template.tags['custom'].equal?(original_klass)
  ensure
    Object.send(:remove_const, :CustomTag)
    Template.tags.delete('custom')
    Liquid.cache_classes = original_cache_setting
  end

  def test_without_cache_classes_tags_reloads_the_class
    original_cache_setting = Liquid.cache_classes
    Liquid.cache_classes = false

    original_klass = Class.new
    Object.send(:const_set, :CustomTag, original_klass)
    Template.register_tag('custom', CustomTag)

    Object.send(:remove_const, :CustomTag)

    new_klass = Class.new
    Object.send(:const_set, :CustomTag, new_klass)

    assert Template.tags['custom'].equal?(new_klass)
  ensure
    Object.send(:remove_const, :CustomTag)
    Template.tags.delete('custom')
    Liquid.cache_classes = original_cache_setting
  end

  class FakeTag; end

  def test_tags_delete
    Template.register_tag('fake', FakeTag)
    assert_equal FakeTag, Template.tags['fake']

    Template.tags.delete('fake')
    assert_nil Template.tags['fake']
  end
end
