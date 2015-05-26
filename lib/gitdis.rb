require 'open3'  # used for rudimentary git pull
require 'digest' # md5sum
require 'redis'

class GitDis
  # return Process::Status, stream through STDOUT and STDERR
  def self.exec(cmd, bytes=1024)
    Open3.popen3(cmd) { |sin, sout, serr, thr|
      sin.close_write
      while !sout.eof or !serr.eof
        ready = IO.select [sout, serr]
        if ready
          ready[0].each { |f| # ready for reading
            begin
              (f == sout ? $stdout : $stderr).print f.read_nonblock(bytes)
            rescue EOFError => e
              # ok
            end
          }
        end
      end
      thr.value # Process::Status
    }
  end

  # raise on nonzero exit code
  def self.exec!(cmd)
    status = self.exec(cmd)
    raise "`#{cmd}` #{status}" unless status.exitstatus == 0
    0
  end

  # file contents, version, md5
  def self.keyset(base_key)
    [base_key, [base_key, 'version'].join(':'), [base_key, 'md5'].join(':')]
  end

  def self.dump(keys, redis_options)
    redis = Redis.new(redis_options)
    keys.each { |base_key|
      self.keyset(base_key).each { |rkey|
        val = redis.get(rkey)
        if val and val.include?("\n")
          val = "\n" << val.split("\n").map { |line| "\t#{line}" }.join("\n")
        end
        puts ["[#{rkey}]", val].join(' ')
      }
    }
    redis.disconnect
  end

  attr_accessor :repo_dir, :redis

  def initialize(repo_dir, redis_options = {})
    raise "#{repo_dir} does not exist!" unless Dir.exist? repo_dir
    @repo_dir = repo_dir
    @redis = Redis.new(redis_options)
  end

  def git_pull(git_branch)
    Dir.chdir @repo_dir do
      if self.class.exec("git diff --quiet HEAD").exitstatus != 0
        raise "please stash your local changes"
      end
      self.class.exec! "git checkout #{git_branch}"
      self.class.exec! "git pull"
    end
    self
  end

  # update only if the local file exists and has a different md5 than redis
  def update(keymap)
    keymap.each { |base_key, relpath|
      # does file exist?
      abspath = File.join(@repo_dir, relpath)
      unless File.exist? abspath
        puts "#{abspath} does not exist; skipping..."
        next
      end

      # check md5
      md5 = Digest::MD5.file(abspath).hexdigest
      fkey, vkey, mkey = self.class.keyset(base_key)
      if @redis.get(mkey) == md5
        puts "#{relpath} md5 matches redis; nothing to do"
        next
      end

      # update redis
      puts "updating [#{fkey}]"
      @redis.set(fkey, File.read(abspath))
      @redis.set(mkey, md5)
      ver = @redis.incr(vkey)
      puts "\tversion #{ver} (#{md5})"
    }
    self
  end
end
