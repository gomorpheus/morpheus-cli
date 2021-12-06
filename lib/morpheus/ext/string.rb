class String
  
  def pluralize
    value = self.dup
    if value == ""
      value
    elsif value[-1].chr == "y"
      value[0..-2] + "ies"
    elsif value[-1].chr == "s"
      if value[-2..-1] == "es"
        value
      else
        value + "es"
      end
    else
      value + "s"
    end
  end

  def singularize
    value = self.dup
    if value == ""
      value
    elsif value.size > 3 && value[-3..-1] == "ies"
      value[0..-4] + "y"
    elsif value.size > 2 && value[-3..-1] == "ses"
      value[0..-3]
    elsif value[-1] == "s"
      value[0..-2]
    else
      value
    end
  end

  def underscore
    value = self.dup
    value.gsub!(/::/, '/')
    value.gsub!(/([A-Z]+)([A-Z][a-z])/,'\1_\2')
    value.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
    value.tr!("-", "_")
    value.tr!(" ", "_")
    value.downcase!
    value
  end

  def camelcase
    value = self.underscore.gsub(/\_([a-z])/) do $1.upcase end
    value = value[0, 1].downcase + value[1..-1]
    value
  end

  def upcamelcase
    self.camelcase.capitalize
  end

  def titleize
    self.underscore.split("_").map(&:capitalize).join(" ")
  end

  def dasherize
    self.underscore.gsub("_", "-")
  end

end
