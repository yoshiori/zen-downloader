# frozen_string_literal: true

require "spec_helper"

RSpec.describe ZenDownloader::Exercise do
  let(:section) do
    ZenDownloader::Section.new(
      "id" => 65_270_556_164,
      "title" => "クロス集計表 確認テスト",
      "resource_type" => "exercise",
      "content_url" => "https://www.nnn.ed.nico/contents/courses/1/chapters/2/exercises/3/result?content_type=zen_univ"
    )
  end

  let(:multiple_choice_init) do
    {
      "materialMeta" => {
        "learningMaterialCode" => "TZGEJGK",
        "type" => "evaluation_exercises",
        "title" => "統計学入門 問題"
      },
      "userContext" => {
        "passed" => true,
        "answers" => {
          "qid-1" => { "answering" => "3", "isCorrect" => true }
        },
        "history" => { "first" => { "score" => 1 } }
      }
    }
  end

  describe "with a multiple choice question" do
    let(:page_data) do
      {
        "init" => multiple_choice_init,
        "statement_text" => "クロス集計表とは何でしょうか？",
        "statement_html" => "<p>クロス集計表とは何でしょうか？</p>",
        "items" => [
          {
            "id" => "qid-1",
            "type" => "normal",
            "badge" => "shoumon-badge-correct",
            "choices" => [
              { "value" => "1", "text" => "誤り1", "html" => "<p>誤り1</p>" },
              { "value" => "3", "text" => "正解",  "html" => "<p>正解</p>" }
            ],
            "textarea_value" => nil,
            "text_input_value" => nil,
            "explanation_text" => nil,
            "explanation_html" => nil
          }
        ]
      }
    end

    it "exposes material metadata" do
      exercise = described_class.new(section: section, page_data: page_data)
      expect(exercise.learning_material_code).to eq("TZGEJGK")
      expect(exercise.material_type).to eq("evaluation_exercises")
    end

    it "merges the SSR'd choices with the user's answer from kokuban-init" do
      exercise = described_class.new(section: section, page_data: page_data)
      q = exercise.questions.first
      expect(q["id"]).to eq("qid-1")
      expect(q["user_answer"]).to eq("3")
      expect(q["is_correct"]).to be(true)
      expect(q["choices"].length).to eq(2)
    end

    it "serializes to a hash with statement and questions" do
      hash = described_class.new(section: section, page_data: page_data).to_h
      expect(hash["title"]).to eq("クロス集計表 確認テスト")
      expect(hash["resource_type"]).to eq("exercise")
      expect(hash["learning_material_code"]).to eq("TZGEJGK")
      expect(hash["statement_text"]).to eq("クロス集計表とは何でしょうか？")
      expect(hash["questions"].first["user_answer"]).to eq("3")
    end
  end

  describe "with a short-answer (word) question" do
    # Word questions have no name attribute on the SSR'd input so the id
    # only lives in kokuban-init.answers and must be paired by index.
    let(:page_data) do
      {
        "init" => {
          "materialMeta" => { "type" => "evaluation_exercises" },
          "userContext" => {
            "answers" => { "word-id" => { "answering" => "0.48", "isCorrect" => true } }
          }
        },
        "statement_text" => "χ²を計算してください．",
        "items" => [
          {
            "id" => nil,
            "type" => "word",
            "badge" => "shoumon-badge-correct",
            "choices" => [],
            "textarea_value" => nil,
            "text_input_value" => "0.48",
            "explanation_text" => "解説",
            "explanation_html" => "<p>解説</p>"
          }
        ]
      }
    end

    it "fills in the question id from kokuban-init when SSR didn't expose it" do
      exercise = described_class.new(section: section, page_data: page_data)
      q = exercise.questions.first
      expect(q["id"]).to eq("word-id")
      expect(q["user_answer"]).to eq("0.48")
      expect(q["is_correct"]).to be(true)
      expect(q["explanation_text"]).to eq("解説")
    end
  end

  describe "with an essay (textarea) question on a report" do
    let(:report_section) do
      ZenDownloader::Section.new(
        "id" => 7,
        "title" => "確認レポート",
        "resource_type" => "report",
        "content_url" => "https://www.nnn.ed.nico/contents/courses/1/chapters/2/reports/3/result?content_type=zen_univ"
      )
    end

    let(:page_data) do
      {
        "init" => {
          "materialMeta" => { "type" => "essay_reports" },
          "userContext" => {
            "answers" => { "essay-id" => { "answering" => "私の回答", "isCorrect" => nil } }
          }
        },
        "statement_text" => "説明してください．",
        "items" => [
          {
            "id" => nil,
            "type" => "essay",
            "badge" => nil,
            "choices" => [],
            "textarea_value" => "私の回答",
            "text_input_value" => nil
          }
        ]
      }
    end

    it "captures the textarea value as the user answer" do
      exercise = described_class.new(section: report_section, page_data: page_data)
      q = exercise.questions.first
      expect(q["id"]).to eq("essay-id")
      expect(q["type"]).to eq("essay")
      expect(q["user_answer"]).to eq("私の回答")
      expect(q["is_correct"]).to be_nil
    end

    it "marks the section as a report" do
      hash = described_class.new(section: report_section, page_data: page_data).to_h
      expect(hash["resource_type"]).to eq("report")
      expect(hash["material_type"]).to eq("essay_reports")
    end
  end
end
