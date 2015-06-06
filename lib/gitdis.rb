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

  # concatenate file contents into a single string
  # separate by newlines, including CRs if any CRs are detected anywhere
  # include a filetype-specific separator if recognized
  # filenames is an array, and all lengths 0-N are handled
  def self.concatenate(filenames)
    filetypes = filenames.map { |fname| File.extname(fname) }.uniq
    case filetypes.length
    when 0
      return "" if filenames.length == 0
      raise "filetype detection failure: #{filenames}"
    when 1
      sep = self.separator(filetypes.first)
    else
      raise "refusing to concatenate disparate filetypes: #{filetypes}"
    end

    payload = filenames.map { |fname|
      contents = File.read(fname) || raise("could not read #{fname}")
      sep << "\r" if !sep.include?("\r") and contents.include?("\r")
      contents if !contents.empty?
    }.compact.join("#{sep}\n")
  end

  # return a specific separator for known filetypes
  # e.g. yaml document separator: ---
  def self.separator(filetype)
    filetype = filetype[1..-1] if filetype[0] == '.'
    case filetype.downcase
    when 'yaml', 'yml'
      '---'
    else
      ''
    end
  end

  attr_accessor :repo_dir, :redis, :dry_run

  def initialize(repo_dir, redis_options = {})
    @dry_run = false
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
  # return true if dry run and update needed
  # otherwise update contents and md5; increment version
  def update_redis(base_key, file_contents)
    md5 = Digest::MD5.hexdigest(file_contents)
    fkey, vkey, mkey = self.class.keyset(base_key)
    return false if @redis.get(mkey) == md5

    if @dry_run
      true
    else
      @redis.set(fkey, file_contents)
      @redis.set(mkey, md5)
      ver = @redis.incr(vkey)
      [ver, md5]
    end
  end

  # e.g. update('foo:bar:baz', 'foo/bar/*.baz')
  # return nil        # path does not exist
  #        false      # no update needed
  #        true       # update was needed, but just a dry run
  #        [ver, md5] # updated
  def update(base_key, relpath)
    # handle e.g. "foo/bar/*.yaml"
    files = Dir.glob(File.join(@repo_dir, relpath))
    case files.length
    when 0 then nil
    when 1 then self.update_redis(base_key, File.read(files.first))
    else        self.update_redis(base_key, self.class.concatenate(files))
    end
  end
end
