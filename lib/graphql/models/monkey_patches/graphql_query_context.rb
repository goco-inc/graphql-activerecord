class GraphQL::Query::Context
  def include?(item)
    !!(@values && @values.include?(item))
  end

  def ability
    @values[:ability] if include?(:ability)
  end

  def can?(action, subject, *extra_args)
    return true unless ability
    ability.can?(action, subject, *extra_args)
  end

  def authorize!(action, subject, *extra_args)
    return unless ability

    unless ability.can?(action, subject, *extra_args)
      details = {
        action: action,
        subject_type: subject.is_a?(ActiveRecord::Base) ? subject.class.name : subject.name,
        subject_id: subject.respond_to?(:gid) ? subject.gid : nil,
        subject_rid: subject.is_a?(ActiveRecord::Base) ? subject.id : nil
      }

      fail GraphErrors.unauthorized("You are not authorized to #{details[:action].to_s.titleize.downcase} this #{details[:subject_type].to_s.titleize.downcase}.", details)
    end
  end
end
