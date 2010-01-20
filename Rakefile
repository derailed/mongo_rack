begin
  require 'bones'
  Bones.setup
rescue LoadError
  begin
    load 'tasks/setup.rb'
  rescue LoadError
    raise RuntimeError, '### please install the "bones" gem ###'
  end
end

ensure_in_path 'lib'
require 'mongo_rack'

task :default => 'spec:run'

PROJ.name      = 'mongo_rack'
PROJ.version   = "0.0.3"
PROJ.authors   = 'Fernand Galiana'
PROJ.email     = 'fernand.galiana@gmail.com'
PROJ.url       = 'http://github.com/derailed/mongo_rack'
PROJ.summary   = "Rackable mongoDB based session management"
PROJ.ruby_opts = %w[-W0]
PROJ.readme    = 'README.rdoc'
PROJ.rcov.opts = ["--sort", "coverage", "-T"]
PROJ.spec.opts << '--color'

# Dependencies
depend_on "rack"     , ">= 1.0.1"
depend_on "mongo"    , ">= 0.18.2"
depend_on "mongo_ext", ">= 0.18.2"
