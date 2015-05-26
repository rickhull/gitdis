Gem::Specification.new do |s|
  s.name = 'gitdis'
  s.summary = 'Pull from git, push to redis and beyond!'
  s.author = 'Rick Hull'
  s.homepage = 'https://github.com/rickhull/gitdis'
  s.license = 'MIT'
  s.description = 'Should you use this?  YES!'

  s.required_ruby_version = '>= 2.0'

  s.add_runtime_dependency 'slop', '~> 4.0'
  s.add_runtime_dependency 'redis', '~> 3.0'

  s.add_development_dependency 'buildar', '~> 2'

  # set version dynamically from version file contents
  s.version  = File.read(File.join(__dir__, 'VERSION')).chomp

  s.files = %w[
    VERSION
    README.md
    lib/gitdis.rb
    bin/gitdis
  ]

  s.executables << 'gitdis'
end
