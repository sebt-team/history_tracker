module ActiveAudit
  module ActiveRecord
    module InstanceMethods
      def audited_changes
        association_chain = [{ id: id, name: self.class.name }]
        audit_class.where(scope: audit_options[:scope], association_chain: association_chain)
      end

      private
      def transform_changes(changes)
        original = {}
        modified = {}
        changes.each_pair do |k, v|
          o, m = v
          original[k] = o unless o.nil?
          modified[k] = m unless m.nil?
        end

        [ original, modified ]
      end

      def audited_attributes(method)
        @audited_attributes = {
          association_chain: [{ id: id, name: self.class.name }],
          scope:             audit_options[:scope],
          action:            method,
          modifier_id:       ActiveAudit.current_modifier.id
        }

        original, modified = transform_changes(case method
          when :create
            audited_attributes_for_create
          when :destroy
            audited_attributes_for_destroy
          else
            audited_attributes_for_update
        end)

        @audited_attributes[:original] = original
        @audited_attributes[:modified] = modified
        @audited_attributes
      end

      def audited_attributes_for_create
        attributes.inject({}) do |h, pair|
          k,v  =  pair
          h[k] = [nil, v]
          h
        end.reject do |k, v|
          non_audited_columns.include?(k)
        end
      end

      def audited_attributes_for_update
        changes.except(*non_audited_columns)
      end

      def audited_attributes_for_destroy
        attributes.inject({}) do |h, pair|
          k,v  =  pair
          h[k] = [nil, v]
          h
        end
      end

      def audit_create
        audit_class.create!(audited_attributes(:create))
      end

      def audit_update
        audit_class.create!(audited_attributes(:update))
      end

      def audit_destroy
        audit_class.create!(audited_attributes(:destroy))
      end
    end
  end
end