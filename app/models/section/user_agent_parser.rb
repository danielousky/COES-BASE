class Section
  module UserAgentParser
    module_function

    def call(ua)
      return nil if ua.blank?
      label = "#{os(ua)} . #{browser(ua)}"
      label.gsub(/\s*\.\s*\z/, '')
    end

    def os(ua)
      case ua
      when /Windows NT 10/    then 'Windows 10/11'
      when /Windows NT 6\.3/  then 'Windows 8.1'
      when /Windows NT 6\.2/  then 'Windows 8'
      when /Windows NT 6\.1/  then 'Windows 7'
      when /Windows/          then 'Windows'
      when /iPhone|iPad|iPod/ then ios_version(ua)
      when /Android/          then android_version(ua)
      when /Mac OS X/         then mac_version(ua)
      when /CrOS/             then 'ChromeOS'
      when /Linux/            then 'Linux'
      else 'Otro'
      end
    end

    def browser(ua)
      case ua
      when /Edg\//     then "Edge"
      when /OPR\//     then "Opera"
      when /Chrome\//  then "Chrome #{ua[/Chrome\/([\d]+)/, 1]}".strip
      when /Firefox\// then "Firefox #{ua[/Firefox\/([\d]+)/, 1]}".strip
      when /Safari\//  then "Safari #{ua[/Version\/([\d.]+)/, 1]}".strip
      else ''
      end
    end

    def ios_version(ua)
      version = ua[/OS (\d+[_\d]*) like Mac/, 1]
      version = version.to_s.tr('_', '.')
      device = ua.match?(/iPad/) ? 'iPad' : (ua.match?(/iPod/) ? 'iPod' : 'iPhone')
      version.present? ? "#{device} iOS #{version}" : device
    end

    def android_version(ua)
      version = ua[/Android (\d+[\.\d]*)/, 1]
      version.present? ? "Android #{version}" : 'Android'
    end

    def mac_version(ua)
      version = ua[/Mac OS X (\d+[_\d]*)/, 1]
      version = version.to_s.tr('_', '.')
      version.present? ? "macOS #{version}" : 'macOS'
    end
  end
end
