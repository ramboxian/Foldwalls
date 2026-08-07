import {defineField, defineType} from 'sanity'

export const localizedTag = defineType({
  name: 'localizedTag',
  title: '双语搜索标签',
  type: 'object',
  fields: [
    defineField({name: 'zh', title: '中文', type: 'string', validation: (rule) => rule.max(40)}),
    defineField({name: 'en', title: 'English', type: 'string', validation: (rule) => rule.max(60)}),
  ],
  validation: (rule) => rule.custom((value) => {
    if (!value || value.zh?.trim() || value.en?.trim()) return true
    return '中文或英文至少填写一项'
  }),
  preview: {
    select: {zh: 'zh', en: 'en'},
    prepare({zh, en}) {
      return {title: `${zh || '—'} / ${en || '—'}`}
    },
  },
})
