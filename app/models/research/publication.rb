# == Schema Information
#
# Table name: research_publications
#
#  id               :uuid             not null, primary key
#  abstract         :text
#  authors_citeproc :json
#  authors_list     :text
#  citation_full    :text
#  data             :jsonb
#  doi              :string
#  file             :text
#  hal_docid        :string           indexed
#  hal_url          :string
#  journal_title    :string
#  open_access      :boolean
#  publication_date :date
#  ref              :string
#  slug             :string           indexed
#  source           :integer          default("osuny")
#  title            :string
#  url              :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_research_publications_on_hal_docid  (hal_docid)
#  index_research_publications_on_slug       (slug)
#
class Research::Publication < ApplicationRecord
  include AsIndirectObject
  include Sanitizable
  include Sluggable
  include WithCitations
  include WithGitFiles
  include WithPermalink

  has_and_belongs_to_many :researchers,
                          class_name: 'University::Person',
                          foreign_key: :university_person_id,
                          association_foreign_key: :research_publication_id

  has_and_belongs_to_many :authors,
                          class_name: 'Research::Hal::Author',
                          foreign_key: :research_hal_author_id,
                          association_foreign_key: :research_publication_id

  validates_presence_of :docid

  scope :ordered, -> { order(publication_date: :desc)}

  enum source: {
    osuny: 0,
    hal: 1
  }

  def editable?
    source == :osuny
  end

  # https://api.archives-ouvertes.fr/search/?q=03713859&fl=*
  def self.import_from_hal_for_author(author)
    fields = [
      'docid',
      'title_s',
      'citationRef_s',
      'citationFull_s',
      'uri_s',
      'doiId_s',
      'publicationDate_tdate',
      'linkExtUrl_s',
      'abstract_s',
      'openAccess_bool',
      'journalTitle_s',
      'authFullName_s',
      'authLastName_s',
      'authFirstName_s',
      'files_s'
      # '*',
    ]
    publications = []
    response = HalOpenscience::Document.search "authIdFormPerson_s:#{author.docid}", fields: fields, limit: 1000
    response.results.each do |doc|
      publication = create_from doc
      publications << publication
    end
    publications
  end

  def self.create_from(doc)
    publication = where(hal_docid: doc.docid).first_or_create
    puts "HAL sync publication #{doc.docid}"
    publication.title = Osuny::Sanitizer.sanitize doc.title_s.first, 'string'
    publication.ref = doc.attributes['citationRef_s']
    publication.citation_full = doc.attributes['citationFull_s']
    publication.abstract = doc.attributes['abstract_s']&.first
    publication.hal_url = doc.attributes['uri_s']
    publication.doi = doc.attributes['doiId_s']
    publication.publication_date = doc.attributes['publicationDate_tdate']
    publication.url = doc.attributes['linkExtUrl_s']
    publication.open_access = doc.attributes['openAccess_bool']
    publication.journal_title = doc.attributes['journalTitle_s']
    publication.file = doc.attributes['files_s']&.first
    publication.authors_list = doc.attributes['authFullName_s'].join(', ')
    publication.authors_citeproc = []
    doc.attributes['authLastName_s'].each_with_index do |last_name, index|
      publication.authors_citeproc << {
        "family" => last_name, 
        "given" => doc.attributes['authFirstName_s'][index]
      }
    end
    publication.save
    publication
  end

  def template_static
    "admin/research/publications/static"
  end

  def git_path(website)
    "#{git_path_content_prefix(website)}publications/#{publication_date.year}/#{slug}.html" if for_website?(website)
  end

  def doi_url
    Doi.url doi
  end

  def best_url
    url || doi_url || hal_url
  end

  def to_s
    "#{title}"
  end

  protected

  def to_citeproc(website: nil)
    {
      "title" => title,
      "author" => authors_citeproc,
      "URL" => hal_url,
      "container-title" => journal_title,
      "pdf" => file,
      "month-numeric" => publication_date.present? ? publication_date.month.to_s : nil,
      "issued" => publication_date.present? ? { "date-parts" => [[publication_date.year, publication_date.month]] } : nil,
      "id" => docid
    }
  end

  def slug_unavailable?(slug)
    self.class.unscoped
              .where(slug: slug)
              .where.not(id: self.id)
              .exists?
  end
end
