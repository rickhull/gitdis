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
          puts ["[#{rkey}]", val].join(' ')
        end
      }
    }
  end

  attr_accessor :repo_dir, :redis

  def initialize(repo_dir, redis_options = {})
    @repo_dir = File.expand_path(repo_dir)
    raise "#{@repo_dir} does not exist!" unless Dir.exist? @repo_dir
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

  # quick false if calculated md5 == redis md5
  # otherwise update contents and md5; increment version
  def update_redis(base_key, file_contents)
    md5 = Digest::MD5.hexdigest(file_contents)
    fkey, vkey, mkey = self.class.keyset(base_key)
    return false if @redis.get(mkey) == md5

    @redis.set(fkey, file_contents)
    @redis.set(mkey, md5)
    ver = @redis.incr(vkey)
    [ver, md5]
  end

  # e.g. update('foo:bar:baz', 'foo/bar/*.baz')
  # return nil        # path does not exist
  #        false      # no update needed
  #        [ver, md5] # updated
  def update(base_key, relpath)
    # handle e.g. "foo/bar/*.yaml"
    files = Dir.glob(File.join(@repo_dir, relpath))
    case files.length
    when 0 then nil
    when 1 then self.update_redis(base_key, File.read(files.first))
    else
      puts "concatenating #{files.length} files"
      sep = "\n"

      payload = files.map { |fname|
        contents = File.read(fname)
        if contents and !contents.empty?
          # scan for carriage returns (Microsoft text format)
          sep = "\r\n" if sep == "\n" and contents.include?("\r")
          contents
        # debugging
        elsif contents
          puts "#{fname} is empty"
          nil
        else
          puts "File.read(#{fname}) returned false/nil"
          nil
        end
      }.compact.join("---#{sep}")

      self.update_redis(base_key, payload)
    end
  end
end
