# 단지카 문서 모음

| 문서 | 경로 | 용도 |
|------|------|------|
| 입주민 이용 매뉴얼 | [manual/입주민-이용-매뉴얼.md](manual/입주민-이용-매뉴얼.md) | A4 PDF 제작용 (스크린샷 자리 표시) |
| 관리자 교육 PPT 스크립트 | [training/관리자-교육-PPT-발표스크립트.md](training/관리자-교육-PPT-발표스크립트.md) | 슬라이드별 발표 원고 |
| Executive Summary | [investor/Executive-Summary.md](investor/Executive-Summary.md) | 투자·제안 1페이지 요약 |
| 운영정책 통합본 | [policy/운영정책-통합본.md](policy/운영정책-통합본.md) | 약관·FAQ·운영규정 |

## PDF / PPT 변환

```bash
# Pandoc 예시 (설치 시)
pandoc docs/manual/입주민-이용-매뉴얼.md -o 단지카-입주민-매뉴얼.pdf
```

- 스크린샷: `docs/manual/screenshots/` 에 매뉴얼 표기 파일명으로 저장 후 PDF에 삽입
- PPT: `training/관리자-교육-PPT-발표스크립트.md` 슬라이드 제목·bullet을 PowerPoint에 복사

기준: 앱 소스 `lib/screens`, `lib/utils`, `support_pages.dart` (2026.06)
