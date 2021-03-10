module NL
  module KNC
    # For running a subset of commands via sudo for the system settings page.
    # Only authorized commands set to NOPASSWD in /etc/sudoers will work.  Will
    # only run sudo if it exists in /usr/bin/sudo or /bin/sudo.  Uses
    # EventMachine::system().
    # TODO: Move into a library, share with logic status page
    module Sudo
      @@sudo_path = ''
      def initialize
        if File.executable?('/usr/bin/sudo')
          @@sudo_path = '/usr/bin/sudo'
        elsif File.executable?('/bin/sudo')
          @@sudo_path = '/bin/sudo'
        else
          log "sudo command not found -- some tasks may not work"
        end
      end

      # Passes the complete command_line to sudo, like this: "sudo -n -- [command_line]".  The
      # block will be passed to EM.system as well.
      def self.sudo command_line, &block
        log "SUDO: Calling sudo: sudo -S -n -- #{command_line}"
        EM.system('/bin/sh', '-c', "sudo -S -n -- #{command_line}") do |*a|
          block.call(*a)
        end
      end
    end
  end
end
