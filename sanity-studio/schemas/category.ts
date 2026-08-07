import {defineField, defineType} from 'sanity'

export const category = defineType({
  name: 'category',
  title: '分类字典',
  type: 'document',
  fields: [
    defineField({
      name: 'key',
      title: '分类标识',
      description: '供客户端稳定识别，创建后不要随意修改。',
      type: 'string',
      readOnly: ({document}) => Boolean(document?._createdAt),
      validation: (rule) => rule.required().regex(/^[a-z][a-z0-9-]*$/),
    }),
    defineField({
      name: 'titleZh',
      title: '中文名称',
      type: 'string',
      validation: (rule) => rule.required().max(30),
    }),
    defineField({
      name: 'titleEn',
      title: '英文名称',
      type: 'string',
      validation: (rule) => rule.required().max(40),
    }),
    defineField({
      name: 'order',
      title: '显示顺序',
      description: '数字越小越靠前。',
      type: 'number',
      initialValue: 999,
      validation: (rule) => rule.required().integer().min(0),
    }),
    defineField({
      name: 'enabled',
      title: '启用',
      type: 'boolean',
      initialValue: true,
    }),
  ],
  orderings: [
    {title: '显示顺序', name: 'displayOrder', by: [{field: 'order', direction: 'asc'}]},
  ],
  preview: {
    select: {titleZh: 'titleZh', titleEn: 'titleEn', enabled: 'enabled'},
    prepare({titleZh, titleEn, enabled}) {
      return {
        title: `${titleZh || '未命名'} / ${titleEn || 'Unnamed'}`,
        subtitle: enabled === false ? '已停用' : '中英一一对应',
      }
    },
  },
})
