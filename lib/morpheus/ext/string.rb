class String
  
  def pluralize
    value = self
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
    value = self
    if value == ""
      value
    elsif value.size > 3 && value[-3..-1] == "ies"
      value[0..-4] + "y"
    elsif value.size > 2 && value[-3..-1] == "ses"
      value[0..-3]
    elsif value[-1] == "s"
      value[0..-2]
    end
  end

  def dasherize
    self.gsub(" ", "-").gsub("_", "-")
  end

  def underscoreize
    self.gsub(" ", "_").gsub("-", "_")
  end

end
