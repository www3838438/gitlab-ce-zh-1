require 'spec_helper'

describe Note, models: true do
  include RepoHelpers

  describe 'associations' do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:noteable).touch(true) }
    it { is_expected.to belong_to(:author).class_name('User') }

    it { is_expected.to have_many(:todos).dependent(:destroy) }
  end

  describe 'modules' do
    subject { described_class }

    it { is_expected.to include_module(Participable) }
    it { is_expected.to include_module(Mentionable) }
    it { is_expected.to include_module(Awardable) }

    it { is_expected.to include_module(Gitlab::CurrentSettings) }
  end

  describe 'validation' do
    it { is_expected.to validate_presence_of(:note) }
    it { is_expected.to validate_presence_of(:project) }

    context 'when note is on commit' do
      before { allow(subject).to receive(:for_commit?).and_return(true) }

      it { is_expected.to validate_presence_of(:commit_id) }
      it { is_expected.not_to validate_presence_of(:noteable_id) }
    end

    context 'when note is not on commit' do
      before { allow(subject).to receive(:for_commit?).and_return(false) }

      it { is_expected.not_to validate_presence_of(:commit_id) }
      it { is_expected.to validate_presence_of(:noteable_id) }
    end

    context 'when noteable and note project differ' do
      subject do
        build(:note, noteable: build_stubbed(:issue),
                     project: build_stubbed(:empty_project))
      end

      it { is_expected.to be_invalid }
    end

    context 'when noteable and note project are the same' do
      subject { create(:note) }
      it { is_expected.to be_valid }
    end

    context 'when project is missing for a project related note' do
      subject { build(:note, project: nil, noteable: build_stubbed(:issue)) }
      it { is_expected.to be_invalid }
    end

    context 'when noteable is a personal snippet' do
      subject { build(:note_on_personal_snippet) }

      it 'is valid without project' do
        is_expected.to be_valid
      end
    end
  end

  describe "Commit notes" do
    let!(:note) { create(:note_on_commit, note: "+1 from me") }
    let!(:commit) { note.noteable }

    it "is accessible through #noteable" do
      expect(note.commit_id).to eq(commit.id)
      expect(note.noteable).to be_a(Commit)
      expect(note.noteable).to eq(commit)
    end

    it "saves a valid note" do
      expect(note.commit_id).to eq(commit.id)
      note.noteable == commit
    end

    it "is recognized by #for_commit?" do
      expect(note).to be_for_commit
    end

    it "keeps the commit around" do
      expect(note.project.repository.kept_around?(commit.id)).to be_truthy
    end
  end

  describe 'authorization' do
    before do
      @p1 = create(:empty_project)
      @p2 = create(:empty_project)
      @u1 = create(:user)
      @u2 = create(:user)
      @u3 = create(:user)
    end

    describe 'read' do
      before do
        @p1.project_members.create(user: @u2, access_level: ProjectMember::GUEST)
        @p2.project_members.create(user: @u3, access_level: ProjectMember::GUEST)
      end

      it { expect(Ability.allowed?(@u1, :read_note, @p1)).to be_falsey }
      it { expect(Ability.allowed?(@u2, :read_note, @p1)).to be_truthy }
      it { expect(Ability.allowed?(@u3, :read_note, @p1)).to be_falsey }
    end

    describe 'write' do
      before do
        @p1.project_members.create(user: @u2, access_level: ProjectMember::DEVELOPER)
        @p2.project_members.create(user: @u3, access_level: ProjectMember::DEVELOPER)
      end

      it { expect(Ability.allowed?(@u1, :create_note, @p1)).to be_falsey }
      it { expect(Ability.allowed?(@u2, :create_note, @p1)).to be_truthy }
      it { expect(Ability.allowed?(@u3, :create_note, @p1)).to be_falsey }
    end

    describe 'admin' do
      before do
        @p1.project_members.create(user: @u1, access_level: ProjectMember::REPORTER)
        @p1.project_members.create(user: @u2, access_level: ProjectMember::MASTER)
        @p2.project_members.create(user: @u3, access_level: ProjectMember::MASTER)
      end

      it { expect(Ability.allowed?(@u1, :admin_note, @p1)).to be_falsey }
      it { expect(Ability.allowed?(@u2, :admin_note, @p1)).to be_truthy }
      it { expect(Ability.allowed?(@u3, :admin_note, @p1)).to be_falsey }
    end
  end

  it_behaves_like 'an editable mentionable' do
    subject { create :note, noteable: issue, project: issue.project }

    let(:issue) { create(:issue, project: create(:project, :repository)) }
    let(:backref_text) { issue.gfm_reference }
    let(:set_mentionable_text) { ->(txt) { subject.note = txt } }
  end

  describe "#all_references" do
    let!(:note1) { create(:note_on_issue) }
    let!(:note2) { create(:note_on_issue) }

    it "reads the rendered note body from the cache" do
      expect(Banzai::Renderer).to receive(:cache_collection_render).
        with([{
          text: note1.note,
          context: {
            skip_project_check: false,
            pipeline: :note,
            cache_key: [note1, "note"],
            project: note1.project,
            author: note1.author
          }
        }]).and_call_original

      expect(Banzai::Renderer).to receive(:cache_collection_render).
        with([{
          text: note2.note,
          context: {
            skip_project_check: false,
            pipeline: :note,
            cache_key: [note2, "note"],
            project: note2.project,
            author: note2.author
          }
        }]).and_call_original

      note1.all_references.users
      note2.all_references.users
    end
  end

  describe "editable?" do
    it "returns true" do
      note = build(:note)
      expect(note.editable?).to be_truthy
    end

    it "returns false" do
      note = build(:note, system: true)
      expect(note.editable?).to be_falsy
    end
  end

  describe "cross_reference_not_visible_for?" do
    let(:private_user)    { create(:user) }
    let(:private_project) { create(:empty_project, namespace: private_user.namespace) { |p| p.team << [private_user, :master] } }
    let(:private_issue)   { create(:issue, project: private_project) }

    let(:ext_proj)  { create(:empty_project, :public) }
    let(:ext_issue) { create(:issue, project: ext_proj) }

    let(:note) do
      create :note,
        noteable: ext_issue, project: ext_proj,
        note: "mentioned in issue #{private_issue.to_reference(ext_proj)}",
        system: true
    end

    it "returns true" do
      expect(note.cross_reference_not_visible_for?(ext_issue.author)).to be_truthy
    end

    it "returns false" do
      expect(note.cross_reference_not_visible_for?(private_user)).to be_falsy
    end

    it "returns false if user visible reference count set" do
      note.user_visible_reference_count = 1

      expect(note).not_to receive(:reference_mentionables)
      expect(note.cross_reference_not_visible_for?(ext_issue.author)).to be_falsy
    end

    it "returns true if ref count is 0" do
      note.user_visible_reference_count = 0

      expect(note).not_to receive(:reference_mentionables)
      expect(note.cross_reference_not_visible_for?(ext_issue.author)).to be_truthy
    end
  end

  describe 'clear_blank_line_code!' do
    it 'clears a blank line code before validation' do
      note = build(:note, line_code: ' ')

      expect { note.valid? }.to change(note, :line_code).to(nil)
    end
  end

  describe '#participants' do
    it 'includes the note author' do
      project = create(:empty_project, :public)
      issue = create(:issue, project: project)
      note = create(:note_on_issue, noteable: issue, project: project)

      expect(note.participants).to include(note.author)
    end
  end

  describe ".grouped_diff_discussions" do
    let!(:merge_request) { create(:merge_request) }
    let(:project) { merge_request.project }
    let!(:active_diff_note1) { create(:diff_note_on_merge_request, project: project, noteable: merge_request) }
    let!(:active_diff_note2) { create(:diff_note_on_merge_request, project: project, noteable: merge_request) }
    let!(:active_diff_note3) { create(:diff_note_on_merge_request, project: project, noteable: merge_request, position: active_position2) }
    let!(:outdated_diff_note1) { create(:diff_note_on_merge_request, project: project, noteable: merge_request, position: outdated_position) }
    let!(:outdated_diff_note2) { create(:diff_note_on_merge_request, project: project, noteable: merge_request, position: outdated_position) }

    let(:active_position2) do
      Gitlab::Diff::Position.new(
        old_path: "files/ruby/popen.rb",
        new_path: "files/ruby/popen.rb",
        old_line: 16,
        new_line: 22,
        diff_refs: merge_request.diff_refs
      )
    end

    let(:outdated_position) do
      Gitlab::Diff::Position.new(
        old_path: "files/ruby/popen.rb",
        new_path: "files/ruby/popen.rb",
        old_line: nil,
        new_line: 9,
        diff_refs: project.commit("874797c3a73b60d2187ed6e2fcabd289ff75171e").diff_refs
      )
    end

    subject { merge_request.notes.grouped_diff_discussions }

    it "includes active discussions" do
      discussions = subject.values

      expect(discussions.count).to eq(2)
      expect(discussions.map(&:id)).to eq([active_diff_note1.discussion_id, active_diff_note3.discussion_id])
      expect(discussions.all?(&:active?)).to be true

      expect(discussions.first.notes).to eq([active_diff_note1, active_diff_note2])
      expect(discussions.last.notes).to eq([active_diff_note3])
    end

    it "doesn't include outdated discussions" do
      expect(subject.values.map(&:id)).not_to include(outdated_diff_note1.discussion_id)
    end

    it "groups the discussions by line code" do
      expect(subject[active_diff_note1.line_code].id).to eq(active_diff_note1.discussion_id)
      expect(subject[active_diff_note3.line_code].id).to eq(active_diff_note3.discussion_id)
    end
  end

  describe "#discussion_id" do
    let(:note) { create(:note) }

    context "when it is newly created" do
      it "has a discussion id" do
        expect(note.discussion_id).not_to be_nil
        expect(note.discussion_id).to match(/\A\h{40}\z/)
      end
    end

    context "when it didn't store a discussion id before" do
      before do
        note.update_column(:discussion_id, nil)
      end

      it "has a discussion id" do
        # The discussion_id is set in `after_initialize`, so `reload` won't work
        reloaded_note = Note.find(note.id)

        expect(reloaded_note.discussion_id).not_to be_nil
        expect(reloaded_note.discussion_id).to match(/\A\h{40}\z/)
      end
    end
  end

  describe '#for_personal_snippet?' do
    it 'returns false for a project snippet note' do
      expect(build(:note_on_project_snippet).for_personal_snippet?).to be_falsy
    end

    it 'returns true for a personal snippet note' do
      expect(build(:note_on_personal_snippet).for_personal_snippet?).to be_truthy
    end
  end

  describe '#to_ability_name' do
    it 'returns snippet for a project snippet note' do
      expect(build(:note_on_project_snippet).to_ability_name).to eq('snippet')
    end

    it 'returns personal_snippet for a personal snippet note' do
      expect(build(:note_on_personal_snippet).to_ability_name).to eq('personal_snippet')
    end

    it 'returns merge_request for an MR note' do
      expect(build(:note_on_merge_request).to_ability_name).to eq('merge_request')
    end

    it 'returns issue for an issue note' do
      expect(build(:note_on_issue).to_ability_name).to eq('issue')
    end

    it 'returns issue for a commit note' do
      expect(build(:note_on_commit).to_ability_name).to eq('commit')
    end
  end

  describe '#cache_markdown_field' do
    let(:html) { '<p>some html</p>'}

    context 'note for a project snippet' do
      let(:note) { build(:note_on_project_snippet) }

      before do
        expect(Banzai::Renderer).to receive(:cacheless_render_field).
          with(note, :note, { skip_project_check: false }).and_return(html)

        note.save
      end

      it 'creates a note' do
        expect(note.note_html).to eq(html)
      end
    end

    context 'note for a personal snippet' do
      let(:note) { build(:note_on_personal_snippet) }

      before do
        expect(Banzai::Renderer).to receive(:cacheless_render_field).
          with(note, :note, { skip_project_check: true }).and_return(html)

        note.save
      end

      it 'creates a note' do
        expect(note.note_html).to eq(html)
      end
    end
  end

  describe 'expiring ETag cache' do
    let(:note) { build(:note_on_issue) }

    it "expires cache for note's issue when note is saved" do
      expect_any_instance_of(Gitlab::EtagCaching::Store)
        .to receive(:touch)
        .with("/#{note.project.namespace.to_param}/#{note.project.to_param}/noteable/issue/#{note.noteable.id}/notes")

      note.save!
    end
  end
end