require 'graphql'

require 'graphql/models/monkey_patches/base_type'
require 'graphql/models/monkey_patches/graphql_relay_global_node_identification'
require 'graphql/models/monkey_patches/graphql_query_context'

# Helpers
require 'graphql/models/definer'

# Order matters...
require 'graphql/models/identification'
require 'graphql/models/identification/attribute_type_definition'
require 'graphql/models/identification/attribute_types'
require 'graphql/models/identification/node_identification'
require 'graphql/models/identification/model_types'
require 'graphql/models/proxy_block'
require 'graphql/models/definition_helpers'
require 'graphql/models/definition_helpers/associations'
require 'graphql/models/model_type_config'
require 'graphql/models/model_type'
