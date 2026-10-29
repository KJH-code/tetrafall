// node 테스트에서 client/ 모듈을 그대로 불러오기: 브라우저 importmap 식 주소 ('/shared/…', 'client 안의 /x.js') 를 파일로 바꿈
export async function resolve(spec, ctx, next) {
  const fromClient = ctx.parentURL && ctx.parentURL.includes('/client/');
  if (spec.startsWith('/shared/')) return next(new URL('../..' + spec, import.meta.url).href, ctx);
  if (fromClient && /^\/[\w-]+\.js$/.test(spec)) return next(new URL('../../client' + spec, import.meta.url).href, ctx);
  return next(spec, ctx);
}
