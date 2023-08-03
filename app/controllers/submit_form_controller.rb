# frozen_string_literal: true

class SubmitFormController < ApplicationController
  layout 'form'

  skip_before_action :authenticate_user!

  def show
    @submitter =
      Submitter.preload(submission: { template: { documents_attachments: { preview_images_attachments: :blob } } })
               .find_by!(slug: params[:slug])

    return redirect_to submit_form_completed_path(@submitter.slug) if @submitter.completed_at?

    cookies[:submitter_sid] = @submitter.signed_id
  end

  def update
    submitter = Submitter.find_by!(slug: params[:slug])
    submitter.values.merge!(normalized_values)
    submitter.completed_at = Time.current if params[:completed] == 'true'
    submitter.opened_at ||= Time.current

    submitter.save!

    Submissions.update_template_fields!(submitter.submission) if submitter.submission.template_fields.blank?

    submitter.submission.save!

    if submitter.completed_at? && !ENV['DESTINATION_EMAIL'].to_s.empty?
      GenerateSubmitterResultAttachmentsJob.perform_later(submitter)

      SubmitterMailer.completed_email(submitter, ENV['DESTINATION_EMAIL']).deliver_later!
    end

    head :ok
  end

  def completed
    @submitter = Submitter.find_by!(slug: params[:submit_form_slug])
  end

  private

  def normalized_values
    params.fetch(:values, {}).to_unsafe_h.transform_values do |v|
      if params[:cast_boolean] == 'true'
        v == 'true'
      else
        v.is_a?(Array) ? v.compact_blank : v
      end
    end
  end
end
