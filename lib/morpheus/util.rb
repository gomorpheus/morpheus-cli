# Provides global utility methods
# Such as opening a web browser to a url
#
module Morpheus::Util

  def self.open_url_command(url)
    cmd = nil
    if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
      cmd = "start #{url}"
    elsif RbConfig::CONFIG['host_os'] =~ /darwin/
      cmd = "open #{url}"
    elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
      cmd = "xdg-open #{url}"
    else
      raise "open_url_command cannot determine host OS"
    end
    return cmd
  end

  def self.open_url(url)
    cmd = open_url_command(url)
    return system(cmd)
  end
end
